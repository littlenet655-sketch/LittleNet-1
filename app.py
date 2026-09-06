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
from quiz.service import quiz_due, needs_onboarding_quiz
from services.controls import controls_for_child, feature_allowed, effective_categories, quiet_hours_state
from services.i18n import language_for_user, tr, LANGUAGES


def create_app():
    app=Flask(__name__);app.config.from_object(Config)
    app.wsgi_app=ProxyFix(app.wsgi_app,x_for=1,x_proto=1,x_host=1,x_port=1)

    def _dynamic_cookie_secure(flask_app):
        if not flask_app.config.get('SESSION_COOKIE_SECURE', False):
            return False
        from flask import has_request_context, request
        if has_request_context() and request:
            return request.is_secure
        return flask_app.config.get('SESSION_COOKIE_SECURE', False)

    app.session_interface.get_cookie_secure = _dynamic_cookie_secure
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

    for bp in [auth_bp,api_bp,child_bp,upload_bp,child_message_bp,parent_bp,parent_api_bp,quiz_bp,admin_bp]:
        app.register_blueprint(bp)

    @app.before_request
    def enforce_kids_controls():
        if session.get('role')!='CHILD':
            return None
        path=request.path
        if path.startswith('/static/') or path.startswith('/uploads/') or path in {'/logout/','/switch-mode/','/language/','/api/usage/heartbeat/','/quiet-hours/'}:
            return None
        if path.startswith('/quiz/'):
            return None

        # First-run onboarding: a newly parent-created child completes two
        # age-matched questions before entering the social feed.
        if needs_onboarding_quiz(session['user_id']):
            return redirect('/quiz/start/?onboarding=1')

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
        key=session.get('usage_session_key')
        if key:heartbeat(key)
        locked,_=lock_state(session['user_id'])
        if locked:return render_template('time_limit_reached.html'),403
        if quiz_due(session['user_id']):return redirect('/quiz/start/')
        return None

    @app.route('/sw.js')
    def service_worker():
        response = send_from_directory('static', 'sw.js', mimetype='application/javascript')
        response.headers['Service-Worker-Allowed'] = '/'
        return response

    @app.route('/uploads/<path:filename>')
    def uploaded_file(filename):
        import os
        uid=session.get('user_id');role=session.get('role')
        if not uid:return ('Unauthorized',401)
        stored='uploads/'+filename
        p=fetch_one('SELECT child_id,moderation_status,is_safe FROM posts WHERE media_path=%s OR story_music_path=%s',(stored,stored))
        if p:
            if role=='CHILD':
                if (p['moderation_status']!='ALLOWED' or not p['is_safe']) and uid!=p['child_id']:return ('Unavailable',404)
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
        is_avatar=filename.startswith('profile_pictures/')
        if not any([p,m,f]) and not is_avatar:return ('Unavailable',404)
        target_dir='uploads'
        if not os.path.exists(os.path.join('uploads',filename)):
            demo_file=os.path.join('static','demo',filename)
            if os.path.exists(demo_file):
                target_dir=os.path.join('static','demo')
        return send_from_directory(target_dir,filename)

    @app.route('/healthz')
    def healthz():
        try:
            row=fetch_one('SELECT 1 ok')
            return jsonify(status='ok',database=bool(row and row['ok']==1))
        except Exception:
            return jsonify(status='degraded',database=False),503

    @app.route('/readyz')
    def readyz():
        import os
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
        mail_ok=bool((os.getenv('SMTP_USER') or os.getenv('MAIL_EMAIL')) and (os.getenv('SMTP_PASSWORD') or os.getenv('MAIL_PASSWORD')))
        ok=db_ok and bool(ai_ok) and mail_ok
        return jsonify(
            status='ready' if ok else 'degraded',
            database=db_ok,
            ai=ai_ok,
            ai_mode=ai_detail,
            mail=mail_ok,
            mail_mode='smtp' if mail_ok else 'not_configured'
        ),(200 if ok else 503)

    @app.after_request
    def security_headers(response):
        if request.path.startswith('/static/'):
            response.headers['Cache-Control'] = 'public, max-age=604800, immutable'
        elif request.path.startswith('/uploads/'):
            response.headers['Cache-Control'] = 'public, max-age=86400'

        response.headers.setdefault('X-Content-Type-Options','nosniff')
        response.headers.setdefault('X-Frame-Options','DENY')
        response.headers.setdefault('Referrer-Policy','same-origin')
        response.headers.setdefault('Permissions-Policy','camera=(self), microphone=(self), geolocation=()')
        response.headers.setdefault('Content-Security-Policy',"default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; font-src 'self' https://fonts.gstatic.com data:; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
        if request.is_secure:response.headers.setdefault('Strict-Transport-Security','max-age=31536000; includeSubDomains')
        return response

    @app.context_processor
    def ui_context():
        uid=session.get('user_id');lang=session.get('language') or (language_for_user(uid) if uid else 'EN')
        if uid:session['language']=lang
        ctrls = session.get('_ctrls') if session.get('role') == 'CHILD' else None
        if ctrls is None and uid and session.get('role') == 'CHILD':
            ctrls = controls_for_child(uid)
            session['_ctrls'] = ctrls
        avatar = session.get('_avatar') if session.get('role') == 'CHILD' else None
        if avatar is None and uid and session.get('role') == 'CHILD':
            prow = fetch_one('SELECT profile_picture FROM child_profiles WHERE child_id=%s', (uid,))
            avatar = (prow or {}).get('profile_picture') or 'uploads/profile_pictures/download.webp'
            session['_avatar'] = avatar
        activity_count = 0
        if uid and session.get('role') == 'CHILD':
            try:
                pending_reqs = fetch_one('SELECT COUNT(*) n FROM followers WHERE following_child_id=%s AND approved=FALSE', (uid,))
                unread_notifs = fetch_one('SELECT COUNT(*) n FROM notifications WHERE user_id=%s AND is_read=FALSE', (uid,))
                activity_count = int((pending_reqs or {}).get('n', 0)) + int((unread_notifs or {}).get('n', 0))
            except Exception:
                activity_count = 0
        return {
            't':lambda key:tr(lang,key),
            'ui_language':lang,
            'ui_languages':LANGUAGES,
            'child_controls':ctrls,
            'child_effective_categories':effective_categories(uid) if uid and session.get('role')=='CHILD' else [],
            'nav_avatar':avatar,
            'unread_activity_count':activity_count,
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
