from werkzeug.middleware.proxy_fix import ProxyFix
from flask import Flask,send_from_directory,session,request,jsonify,redirect,render_template
from config import Config
from extensions import csrf,limiter
from auth.routes import auth_bp
from auth.api import api_bp
from child.routes import child_bp
from uploadPost.routes import upload_bp
from childMessage.routes import child_message_bp
from parent.routes import parent_bp
from parent.api import parent_api_bp
from quiz.routes import quiz_bp
from admin.routes import admin_bp
from database.connection import fetch_one
from services.usage import lock_state,heartbeat
from quiz.service import quiz_due
from services.controls import controls_for_child, feature_allowed, effective_categories, quiet_hours_state
from services.i18n import language_for_user, tr, LANGUAGES

def create_app():
    app=Flask(__name__);app.config.from_object(Config)
    # Railway/Modal terminate TLS before Flask. Honor the single trusted proxy
    # hop so request.is_secure, redirects and HSTS reflect the public HTTPS URL.
    app.wsgi_app=ProxyFix(app.wsgi_app,x_for=1,x_proto=1,x_host=1,x_port=1)
    if Config.BASE_URL.startswith('https://'):
        if Config.SECRET_KEY=='change-me-before-demo' or len(Config.SECRET_KEY)<32:
            raise RuntimeError('Production SECRET_KEY must be a random value of at least 32 characters')
        if Config.AI_SERVICE_URL and not Config.AI_SHARED_SECRET:
            raise RuntimeError('AI_SHARED_SECRET is required when AI_SERVICE_URL is configured')
    csrf.init_app(app);limiter.init_app(app)
    from flask_wtf.csrf import CSRFError
    @app.errorhandler(CSRFError)
    def handle_csrf_error(e):
        if request.path.startswith(('/login', '/switch-mode', '/register', '/logout')):
            session.clear()
            return redirect('/login/?error=Your+session+was+refreshed.+Please+enter+your+credentials+to+continue.')
        return render_template('csrf_error.html', reason=e.description), 400

    for bp in [auth_bp,api_bp,child_bp,upload_bp,child_message_bp,parent_bp,parent_api_bp,quiz_bp,admin_bp]:app.register_blueprint(bp)

    @app.before_request
    def enforce_kids_controls():
        if session.get('role')!='CHILD':return None
        path=request.path
        if path.startswith('/static/') or path.startswith('/uploads/') or path in {'/logout/','/switch-mode/','/language/','/api/usage/heartbeat/','/quiet-hours/'}:return None
        feature=None
        if path.startswith(('/reels/','/api/reels/')):feature='reels'
        elif path.startswith(('/stories/','/story/','/api/story-view/')):feature='stories'
        elif path.startswith(('/messages/','/chat/','/send-message/','/send-media/','/share-post/','/api/chat/','/api/share-post/')):feature='messaging'
        elif path.startswith(('/upload-story/','/api/delete-story/','/api/edit-story-caption/')):feature='stories'
        elif path.startswith('/child/upload-post/'):feature='posting'
        elif path.startswith('/discover/'):feature='discover'
        if feature and not feature_allowed(session['user_id'],feature):
            if path.startswith('/api/') or request.is_json:return jsonify(error='disabled_by_parent',feature=feature),403
            return render_template('feature_restricted.html',feature=feature),403
        quiet=quiet_hours_state(session['user_id'])
        if quiet['active']:
            return render_template('quiet_hours.html',quiet=quiet),403
        if path.startswith('/quiz/'):
            return None
        key=session.get('usage_session_key')
        if key:heartbeat(key)
        locked,_=lock_state(session['user_id'])
        if locked:return render_template('time_limit_reached.html'),403
        if quiz_due(session['user_id']):return redirect('/quiz/start/')
        return None

    @app.route('/uploads/<path:filename>')
    def uploaded_file(filename):
        uid=session.get('user_id');role=session.get('role')
        if not uid:return ('Unauthorized',401)
        stored='uploads/'+filename
        p=fetch_one('SELECT child_id,moderation_status,is_safe FROM posts WHERE media_path=%s OR story_music_path=%s',(stored,stored))
        if p:
            if role=='CHILD':
                if p['moderation_status']!='ALLOWED' or not p['is_safe']:return ('Unavailable',404)
                hidden=fetch_one('SELECT 1 FROM blocked_users WHERE (blocker_id=%s AND blocked_id=%s) OR (blocker_id=%s AND blocked_id=%s)',(uid,p['child_id'],p['child_id'],uid))
                if hidden:return ('Unavailable',404)
            elif role=='PARENT':
                if not fetch_one('SELECT 1 FROM parent_child_map WHERE parent_id=%s AND child_id=%s',(uid,p['child_id'])):return ('Forbidden',403)
        m=fetch_one('SELECT sender_child_id,receiver_child_id,moderation_status FROM child_messages WHERE media_path=%s',(stored,))
        if m:
            if role=='CHILD':
                if uid not in {m['sender_child_id'],m['receiver_child_id']}:return ('Forbidden',403)
                if m['moderation_status']!='ALLOWED' and uid!=m['sender_child_id']:return ('Unavailable',404)
            elif role=='PARENT':
                if not fetch_one('SELECT 1 FROM parent_child_map WHERE parent_id=%s AND child_id=%s',(uid,m['sender_child_id'])):return ('Forbidden',403)
                if m['moderation_status']!='REVIEW':return ('Unavailable',404)
            else:return ('Forbidden',403)
        f=fetch_one('SELECT child_id FROM child_profiles WHERE profile_picture=%s',(stored,))
        if f and role=='CHILD':
            hidden=fetch_one('SELECT 1 FROM blocked_users WHERE (blocker_id=%s AND blocked_id=%s) OR (blocker_id=%s AND blocked_id=%s)',(uid,f['child_id'],f['child_id'],uid))
            if hidden:return ('Unavailable',404)
        if f and role=='PARENT' and not fetch_one('SELECT 1 FROM parent_child_map WHERE parent_id=%s AND child_id=%s',(uid,f['child_id'])):return ('Forbidden',403)
        if not any([p,m,f]):return ('Unavailable',404)
        return send_from_directory('uploads',filename)

    @app.route('/healthz')
    def healthz():
        # Liveness for the web container itself. Keep external AI out of this
        # check so a temporary inference outage does not cause a deploy loop.
        try:
            row=fetch_one('SELECT 1 ok')
            return jsonify(status='ok',database=bool(row and row['ok']==1))
        except Exception:
            return jsonify(status='degraded',database=False),503

    @app.route('/readyz')
    def readyz():
        db_ok=False; ai_ok=None; ai_detail='local'
        try:
            row=fetch_one('SELECT 1 ok'); db_ok=bool(row and row['ok']==1)
        except Exception:
            db_ok=False
        try:
            from safety.remote_client import enabled,health
            if enabled():
                ai=health();ai_ok=bool(ai.get('ok'));ai_detail='remote'
            else:
                ai_ok=True;ai_detail='local'
        except Exception:
            ai_ok=False;ai_detail='remote_unavailable'
        ok=db_ok and bool(ai_ok)
        return jsonify(status='ready' if ok else 'degraded',database=db_ok,ai=ai_ok,ai_mode=ai_detail),(200 if ok else 503)

    @app.after_request
    def security_headers(response):
        response.headers.setdefault('X-Content-Type-Options','nosniff')
        response.headers.setdefault('X-Frame-Options','DENY')
        response.headers.setdefault('Referrer-Policy','same-origin')
        response.headers.setdefault('Permissions-Policy','camera=(self), microphone=(self), geolocation=()')
        response.headers.setdefault('Content-Security-Policy',"default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
        if request.is_secure:response.headers.setdefault('Strict-Transport-Security','max-age=31536000; includeSubDomains')
        return response

    @app.context_processor
    def ui_context():
        uid=session.get('user_id');lang=session.get('language') or (language_for_user(uid) if uid else 'EN')
        if uid:session['language']=lang
        return {
            't':lambda key:tr(lang,key),
            'ui_language':lang,
            'ui_languages':LANGUAGES,
            'child_controls':controls_for_child(uid) if uid and session.get('role')=='CHILD' else None,
            'child_effective_categories':effective_categories(uid) if uid and session.get('role')=='CHILD' else [],
        }

    @app.errorhandler(413)
    def too_large(_):return jsonify(error='upload too large'),413

    @app.errorhandler(404)
    def not_found(e):
        if request.path.startswith('/api/') or 'application/json' in request.headers.get('Accept', ''):
            return jsonify(error='Not Found', path=request.path), 404
        return render_template('404.html'), 404

    @app.errorhandler(500)
    def internal_error(e):
        if request.path.startswith('/api/') or 'application/json' in request.headers.get('Accept', ''):
            return jsonify(error='Internal Server Error'), 500
        return render_template('500.html'), 500
    return app
app=create_app()
if __name__=='__main__':app.run(host='0.0.0.0',port=5000,debug=False)
