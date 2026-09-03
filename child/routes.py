import os,uuid
from flask import Blueprint,render_template,request,redirect,session,jsonify
from extensions import limiter
from decorators import child_required
from child.service import *
from services.social import visible_posts,active_stories,story_visible_to,parent_notify,visible_profile_posts
from services.usage import lock_state,heartbeat
from quiz.service import quiz_due
from database.connection import execute,fetch_one,fetch_all
from safety.moderation_service import evaluate,record
from services.audit import log
from services.controls import quiet_hours_state

child_bp=Blueprint('child',__name__,template_folder='templates')
def _guard():
    if session.get('usage_session_key'): heartbeat(session['usage_session_key'])
    locked,remaining=lock_state(session['user_id'])
    if locked:return render_template('time_limit_reached.html'),403
    if quiz_due(session['user_id']) and request.path not in ['/quiz/start/','/quiz/submit/','/logout/']:return redirect('/quiz/start/')
    return None

def _public_profile_text(form):
    return ' '.join(str(form.get(k,'') or '') for k in ['full_name','school_name','location','current_class','bio'])

@child_bp.route('/child/dashboard/')
@child_required
def dashboard():
    g=_guard()
    if g:return g
    if not profile_exists(session['user_id']):return redirect('/child/create-profile/')
    return render_template('child_dashboard.html',profile=get_child_profile(session['user_id']),stories=active_stories(session['user_id']),posts=visible_posts(session['user_id'],False,12,0),reels=visible_posts(session['user_id'],True,5,0))


@child_bp.route('/stories/')
@child_required
def stories_viewer():
    g=_guard()
    if g:return g
    stories=active_stories(session['user_id'])
    try:start_id=int(request.args.get('start') or 0)
    except (TypeError,ValueError):start_id=0
    start_index=next((i for i,row in enumerate(stories) if row['post_id']==start_id),0)
    return render_template('stories_viewer.html',stories=stories,start_index=start_index)

@child_bp.route('/story/<int:post_id>/')
@child_required
def story_view(post_id):
    if not story_visible_to(session['user_id'],post_id):return ('Story unavailable',404)
    return redirect(f'/stories/?start={post_id}')

@child_bp.route('/api/story-view/<int:post_id>/',methods=['POST'])
@child_required
def record_story_view(post_id):
    story=story_visible_to(session['user_id'],post_id)
    if not story:return jsonify(error='Story unavailable'),404
    execute('INSERT INTO story_views(post_id,child_id) VALUES(%s,%s) ON CONFLICT(post_id,child_id) DO UPDATE SET viewed_at=NOW()',(post_id,session['user_id']))
    return jsonify(ok=True)

@child_bp.route('/child/create-profile/',methods=['GET','POST'])
@child_required
def create_profile():
    if request.method=='POST':
        signals,d=evaluate(session['user_id'],'TEXT',_public_profile_text(request.form))
        if d.action!='ALLOW': return render_template('create_profile.html',error='Profile text could not be published under Kids Mode safety rules.'),400
        create_child_profile(session['user_id'],request.form);replace_profile_tags(session['user_id'],request.form.get('skills','').split(','),request.form.get('interests','').split(','),request.form.get('ambitions','').split(','));parent_notify(session['user_id'],'PROFILE_APPROVAL','Skills/interests/ambitions need approval','/parent/content-approval/');return redirect('/child/dashboard/')
    return render_template('create_profile.html')

@child_bp.route('/child/profile/')
@child_required
def profile():
    c=counts(session['user_id']);ps=visible_profile_posts(session['user_id'],session['user_id']);return render_template('profile.html',profile=get_child_profile(session['user_id']),counts=c,posts=ps)

@child_bp.route('/child/view-profile/<int:user_id>/')
@child_required
def view_profile(user_id):
    if fetch_one('SELECT 1 FROM blocked_users WHERE (blocker_id=%s AND blocked_id=%s) OR (blocker_id=%s AND blocked_id=%s)',(session['user_id'],user_id,user_id,session['user_id'])):return ('Not available',404)
    return render_template('view_profile.html',profile=get_child_profile(user_id),counts=counts(user_id),target_user_id=user_id,is_following=is_following(session['user_id'],user_id),is_pending=is_follow_pending(session['user_id'],user_id),posts=visible_profile_posts(session['user_id'],user_id))

@child_bp.route('/discover/')
@child_required
def discover():
    kids=get_random_children(session['user_id'])
    for k in kids:k['is_following']=is_following(session['user_id'],k['user_id']);k['is_pending']=is_follow_pending(session['user_id'],k['user_id'])
    return render_template('discover.html',children=kids)

@child_bp.route('/follow/<int:child_id>/',methods=['POST'])
@child_required
def follow(child_id):
    if child_id==session['user_id']:return jsonify(status='self'),400
    if is_following(session['user_id'],child_id) or is_follow_pending(session['user_id'],child_id):unfollow_child(session['user_id'],child_id);return jsonify(status='removed')
    follow_child(session['user_id'],child_id);log(session['user_id'],'FOLLOW_REQUEST',{'target':child_id});parent_notify(session['user_id'],'FOLLOW_REQUEST','A new connection request needs approval','/parent/follow-requests/');return jsonify(status='pending')

@child_bp.route('/block/<int:user_id>/',methods=['POST'])
@child_required
def block(user_id):
    if user_id!=session['user_id']:log(session['user_id'],'USER_BLOCKED',{'target':user_id});execute('INSERT INTO blocked_users(blocker_id,blocked_id) VALUES(%s,%s) ON CONFLICT DO NOTHING',(session['user_id'],user_id));execute('DELETE FROM followers WHERE (child_id=%s AND following_child_id=%s) OR (child_id=%s AND following_child_id=%s)',(session['user_id'],user_id,user_id,session['user_id']))
    return redirect('/discover/')

@child_bp.route('/mute/<int:user_id>/',methods=['POST'])
@child_required
def mute(user_id):
    if user_id!=session['user_id']:execute('INSERT INTO muted_users(muter_id,muted_id) VALUES(%s,%s) ON CONFLICT DO NOTHING',(session['user_id'],user_id))
    return redirect(request.referrer or '/child/dashboard/')

@child_bp.route('/notifications/')
@child_required
def notifications():return render_template('notifications.html',items=fetch_all('SELECT * FROM notifications WHERE user_id=%s ORDER BY created_at DESC LIMIT 100',(session['user_id'],)),role='CHILD')

@child_bp.route('/notifications/read/',methods=['POST'])
@child_required
def notifications_read():execute('UPDATE notifications SET is_read=TRUE WHERE user_id=%s',(session['user_id'],));return jsonify(ok=True)

@child_bp.route('/api/time-remaining/')
@child_required
def api_time_remaining():
    locked,remaining=lock_state(session['user_id']);return jsonify(remaining_minutes=remaining,locked=locked)

@child_bp.route('/recommended/')
@child_required
def recommended():
    g=_guard()
    if g:return g
    return render_template('recommended.html',posts=recommended_posts(session['user_id'],30,0),stories=active_stories(session['user_id']))

@child_bp.route('/child/upload-profile-picture/',methods=['POST'])
@child_required
def upload_profile_picture():
    photo=request.files.get('photo')
    if not photo or not photo.filename:return jsonify(error='No photo'),400
    if request.content_length and request.content_length>8*1024*1024:return jsonify(error='Photo too large'),413
    os.makedirs('uploads/profile_pictures',exist_ok=True)
    path=os.path.join('uploads/profile_pictures',f'profile_{session["user_id"]}_{uuid.uuid4().hex}.jpg')
    photo.save(path)
    try:
        from PIL import Image
        Image.open(path).verify()
        sig,d=evaluate(session['user_id'],'IMAGE',path)
        if d.action!='ALLOW':
            try:os.remove(path)
            except OSError:pass
            parent_notify(session['user_id'],'PROFILE_PHOTO_BLOCKED',d.reason,'/parent/safety/')
            return jsonify(status=d.action),400
        execute('UPDATE child_profiles SET profile_picture=%s,updated_at=NOW() WHERE child_id=%s',(path,session['user_id']))
        return jsonify(ok=True,path='/'+path)
    except Exception:
        try:os.remove(path)
        except OSError:pass
        return jsonify(error='Invalid or unsafe photo'),400

@child_bp.route('/api/usage/heartbeat/',methods=['POST'])
@child_required
def usage_heartbeat():
    quiet=quiet_hours_state(session['user_id'])
    if quiet['active']:
        return jsonify(ok=True,locked=False,quiet_hours=True,quiet_start=quiet['start'],quiet_end=quiet['end'],redirect='/quiet-hours/')
    if session.get('usage_session_key'):heartbeat(session['usage_session_key'])
    locked,remaining=lock_state(session['user_id'])
    return jsonify(ok=True,locked=locked,remaining_minutes=remaining,quiet_hours=False,redirect='/child/dashboard/' if not locked else None)

@child_bp.route('/quiet-hours/')
@child_required
def quiet_hours_page():
    quiet=quiet_hours_state(session['user_id'])
    if not quiet['active']:
        return redirect('/child/dashboard/')
    return render_template('quiet_hours.html',quiet=quiet)

@child_bp.route('/report/',methods=['POST'])
@child_required
def report_content():
    kind=(request.form.get('target_type') or '').upper();reason=(request.form.get('reason') or '').strip()
    try:tid=int(request.form.get('target_id',0))
    except:return jsonify(error='invalid target'),400
    if kind not in {'USER','POST','COMMENT','MESSAGE'} or not reason:return jsonify(error='invalid report'),400
    valid=False
    if kind=='USER':valid=bool(fetch_one("SELECT 1 FROM users WHERE user_id=%s AND role='CHILD' AND user_id<>%s",(tid,session['user_id'])))
    elif kind=='POST':
        from services.social import post_visible_to
        valid=bool(post_visible_to(session['user_id'],tid))
    elif kind=='COMMENT':
        row=fetch_one("SELECT post_id FROM comments WHERE comment_id=%s AND moderation_status='ALLOWED'",(tid,));valid=bool(row and post_visible_to(session['user_id'],row['post_id']))
    elif kind=='MESSAGE':valid=bool(fetch_one('SELECT 1 FROM child_messages WHERE child_message_id=%s AND (sender_child_id=%s OR receiver_child_id=%s)',(tid,session['user_id'],session['user_id'])))
    if not valid:return jsonify(error='target unavailable'),404
    execute('INSERT INTO reports(reporter_id,target_type,target_id,reason,details) VALUES(%s,%s,%s,%s,%s)',(session['user_id'],kind,tid,reason[:100],(request.form.get('details') or '')[:2000]))
    return jsonify(ok=True)

def _check_live_frame(frame):
    os.makedirs('uploads/live',exist_ok=True)
    path=os.path.join('uploads/live',f'{uuid.uuid4().hex}.jpg');frame.save(path)
    try:
        from PIL import Image
        Image.open(path).verify()
        sig,d=evaluate(session['user_id'],'IMAGE',path)
        # Live monitoring does not retain frames. Only REVIEW/BLOCK decisions are periodically logged.
        if d.action!='ALLOW':
            import time
            now=time.time();last=float(session.get('last_live_safety_event',0) or 0)
            if now-last>=30:
                from safety.moderation_service import record
                event_id=record(session['user_id'],'LIVE_FRAME',None,sig,d)
                # Live frames are intentionally ephemeral, so they are audit/alert events rather
                # than parent-approvable content. Do not leave an empty REVIEW item in the queue.
                execute("UPDATE moderation_events SET status='RESOLVED' WHERE event_id=%s",(event_id,))
                parent_notify(session['user_id'],'LIVE_SAFETY_'+d.action,
                    'Live Safety detected content that was '+('blocked.' if d.action=='BLOCK' else 'flagged.'),
                    '/parent/notifications/')
                session['last_live_safety_event']=now
        return {'decision':d.action,'reason':d.reason,'risk':d.risk,'adult_score':round(float(sig.get('adult_score',0))*100,1),'weapon_score':round(float(sig.get('weapon_score',0))*100,1),'violence_score':round(float(sig.get('violence_score',0))*100,1)}
    finally:
        try:os.remove(path)
        except OSError:pass

@child_bp.route('/live-safety/',methods=['GET','POST'])
@child_required
def live_safety():
    result=None
    if request.method=='POST':
        frame=request.files.get('frame')
        if frame:
            try:result=_check_live_frame(frame)
            except Exception:result={'decision':'BLOCK','reason':'Live safety check unavailable: fail closed','risk':100}
    return render_template('live_safety.html',result=result)

@child_bp.route('/api/live-safety/check/',methods=['POST'])
@child_required
@limiter.limit('45 per minute')
def live_safety_api():
    frame=request.files.get('frame')
    if not frame:return jsonify(error='frame required'),400
    try:return jsonify(_check_live_frame(frame))
    except Exception:return jsonify(decision='BLOCK',reason='Live safety check unavailable: fail closed',risk=100),503

@child_bp.route('/api/following/')
@child_required
def api_following():
    rows=fetch_all('SELECT u.user_id,u.full_name FROM followers f JOIN users u ON u.user_id=f.following_child_id WHERE f.child_id=%s AND f.approved=TRUE',(session['user_id'],))
    return jsonify(rows)

@child_bp.route('/api/share-post/',methods=['POST'])
@child_required
def api_share_post():
    data=request.get_json(silent=True) or {}
    try:receiver=int(data.get('receiver_id'));post_id=int(data.get('post_id'))
    except:return jsonify(error='invalid request'),400
    from services.social import post_visible_to,can_interact
    from childMessage.service import conversation
    if not can_interact(session['user_id'],receiver) or not post_visible_to(session['user_id'],post_id):return jsonify(error='not allowed'),403
    cid=conversation(session['user_id'],receiver);execute("INSERT INTO child_messages(conversation_id,sender_child_id,receiver_child_id,message_type,shared_post_id,moderation_status) VALUES(%s,%s,%s,'SHARED_POST',%s,'ALLOWED')",(cid,session['user_id'],receiver,post_id));return jsonify(ok=True)

@child_bp.route('/time-limit-reached/')
@child_required
def time_limit_reached():return render_template('time_limit_reached.html')

@child_bp.route('/child/edit-profile/',methods=['GET','POST'])
@child_required
def edit_profile():
    if request.method=='POST':
        sig,d=evaluate(session['user_id'],'TEXT',_public_profile_text(request.form))
        if d.action!='ALLOW':return render_template('edit_profile.html',profile=get_child_profile(session['user_id']),error='Profile text could not be published under Kids Mode safety rules.'),400
        execute('UPDATE child_profiles SET full_name=%s,school_name=%s,location=%s,current_class=%s,bio=%s,updated_at=NOW() WHERE child_id=%s',(request.form.get('full_name'),request.form.get('school_name'),request.form.get('location'),request.form.get('current_class'),request.form.get('bio'),session['user_id']));return redirect('/child/profile/')
    return render_template('edit_profile.html',profile=get_child_profile(session['user_id']))

@child_bp.route('/followers/')
@child_required
def followers():return render_template('people_list.html',title='Followers',people=fetch_all('SELECT u.user_id,u.full_name,cp.profile_picture FROM followers f JOIN users u ON u.user_id=f.child_id LEFT JOIN child_profiles cp ON cp.child_id=u.user_id WHERE f.following_child_id=%s AND f.approved=TRUE',(session['user_id'],)))
@child_bp.route('/following/')
@child_required
def following():return render_template('people_list.html',title='Following',people=fetch_all('SELECT u.user_id,u.full_name,cp.profile_picture FROM followers f JOIN users u ON u.user_id=f.following_child_id LEFT JOIN child_profiles cp ON cp.child_id=u.user_id WHERE f.child_id=%s AND f.approved=TRUE',(session['user_id'],)))
@child_bp.route('/unfollow/<int:child_id>/',methods=['POST'])
@child_required
def unfollow(child_id):unfollow_child(session['user_id'],child_id);return redirect('/following/')
