import base64
import json
import os
import random
import tempfile
import uuid
from functools import wraps

from flask import Blueprint,request,jsonify,session,render_template,redirect,g
from extensions import csrf,limiter
from auth.service import login_user,profile_exists
from services.usage import start_session
from database.connection import fetch_one, fetch_all, execute

api_bp=Blueprint('api',__name__)

_AUDIO_EXTS={'mp3','wav','m4a','ogg','aac','flac','wma','opus'}
_MEDIA_POST_PATHS={'/child/upload-post','/upload-story'}


def _registration_error(message, status=400):
    n1=random.randint(14,28);n2=random.randint(13,29)
    return render_template(
        'parent_register_direct.html',
        error=message,
        challenge_q=f'{n1} + {n2}',
        challenge_expected=str(n1+n2),
    ),status


def _masked_email(email):
    local,sep,domain=(email or '').partition('@')
    if not sep:return 'your email address'
    shown=(local[:2]+'***') if len(local)>2 else (local[:1]+'***')
    return f'{shown}@{domain}'


def _all_uploaded_files():
    for field in request.files:
        for item in request.files.getlist(field):
            if item and item.filename:
                yield field,item


def _audio_upload(field,item):
    if field=='music_file':
        return True
    mime=(item.mimetype or '').lower()
    ext=(item.filename.rsplit('.',1)[-1].lower() if '.' in item.filename else '')
    return mime.startswith('audio/') or ext in _AUDIO_EXTS


def _child_media_request():
    path=request.path.rstrip('/')
    return path in _MEDIA_POST_PATHS or path.startswith('/send-media/')


def login_required(fn):
    """Require the short-lived pending-parent registration session for verification routes."""
    @wraps(fn)
    def wrapped(*args,**kwargs):
        if not session.get('pending_parent_user_id') or not session.get('pending_parent_email'):
            return redirect('/register-parent/')
        return fn(*args,**kwargs)
    return wrapped


@api_bp.before_app_request
def locked_media_surface_gate():
    """Retire audio/voice/music and require R2 for child media uploads.

    Files may touch local ephemeral disk only inside the legacy route while AI
    moderation runs. The after-request hook below immediately moves every new
    ALLOWED/REVIEW media object to R2 and stores only its R2 reference in Neon.
    """
    if request.method!='POST' or session.get('role')!='CHILD' or not session.get('user_id'):
        return None

    uploads=list(_all_uploaded_files())
    for field,item in uploads:
        if _audio_upload(field,item):
            return jsonify(
                blocked=True,
                error='Audio, voice messages and story music are not supported in LittleNet.'
            ),400

    if not _child_media_request() or not uploads:
        return None

    from services.object_storage import enabled as r2_enabled
    if not r2_enabled():
        return jsonify(
            error='Media storage is unavailable. LittleNet requires R2 before accepting child media.'
        ),503

    uid=int(session['user_id'])
    path=request.path.rstrip('/')
    if path in _MEDIA_POST_PATHS:
        row=fetch_one('SELECT COALESCE(MAX(post_id),0) AS n FROM posts WHERE child_id=%s',(uid,)) or {'n':0}
        g.littlenet_post_floor=int(row.get('n') or 0)
    if path.startswith('/send-media/'):
        row=fetch_one('SELECT COALESCE(MAX(child_message_id),0) AS n FROM child_messages WHERE sender_child_id=%s',(uid,)) or {'n':0}
        g.littlenet_message_floor=int(row.get('n') or 0)
    return None


def _r2_key(kind,uid,item_id,local_path):
    name=os.path.basename(local_path or 'media.bin').replace(' ','_')
    return f'{kind}/{uid}/{item_id}/{uuid.uuid4().hex}_{name}'


def _unlink_local(path):
    if path and not str(path).startswith('uploads/r2/'):
        try:os.unlink(path)
        except OSError:pass


@api_bp.after_app_request
def persist_child_media_to_r2(response):
    """Finish the moderation->R2->Neon transaction before returning success."""
    if request.method!='POST' or session.get('role')!='CHILD' or not session.get('user_id'):
        return response
    if response.status_code>=400:
        return response

    uid=int(session['user_id'])
    failures=[]
    try:
        from services.object_storage import enabled as r2_enabled, upload_file
        if hasattr(g,'littlenet_post_floor'):
            rows=fetch_all(
                """SELECT post_id,media_path,moderation_status FROM posts
                   WHERE child_id=%s AND post_id>%s AND media_path IS NOT NULL
                     AND media_path NOT LIKE 'uploads/r2/%%'
                     AND moderation_status IN ('ALLOWED','REVIEW')
                   ORDER BY post_id""",
                (uid,int(g.littlenet_post_floor)),
            )
            if rows and not r2_enabled():
                raise RuntimeError('r2_not_configured')
            for row in rows:
                local=row.get('media_path')
                try:
                    ref=upload_file(local,_r2_key('posts',uid,row['post_id'],local))
                    execute('UPDATE posts SET media_path=%s WHERE post_id=%s AND child_id=%s',(ref,row['post_id'],uid))
                    _unlink_local(local)
                except Exception:
                    execute("UPDATE posts SET moderation_status='BLOCKED',is_safe=FALSE,moderation_reason='R2 storage unavailable' WHERE post_id=%s AND child_id=%s",(row['post_id'],uid))
                    _unlink_local(local)
                    failures.append(('POST',row['post_id']))

        if hasattr(g,'littlenet_message_floor'):
            rows=fetch_all(
                """SELECT child_message_id,media_path,moderation_status FROM child_messages
                   WHERE sender_child_id=%s AND child_message_id>%s AND media_path IS NOT NULL
                     AND media_path NOT LIKE 'uploads/r2/%%'
                     AND moderation_status IN ('ALLOWED','REVIEW')
                   ORDER BY child_message_id""",
                (uid,int(g.littlenet_message_floor)),
            )
            if rows and not r2_enabled():
                raise RuntimeError('r2_not_configured')
            for row in rows:
                local=row.get('media_path')
                try:
                    ref=upload_file(local,_r2_key('messages',uid,row['child_message_id'],local))
                    execute('UPDATE child_messages SET media_path=%s WHERE child_message_id=%s AND sender_child_id=%s',(ref,row['child_message_id'],uid))
                    _unlink_local(local)
                except Exception:
                    execute("UPDATE child_messages SET moderation_status='BLOCKED' WHERE child_message_id=%s AND sender_child_id=%s",(row['child_message_id'],uid))
                    _unlink_local(local)
                    failures.append(('MESSAGE',row['child_message_id']))
    except Exception:
        if hasattr(g,'littlenet_post_floor'):
            rows=fetch_all('SELECT post_id,media_path FROM posts WHERE child_id=%s AND post_id>%s',(uid,int(g.littlenet_post_floor)))
            for row in rows:
                execute("UPDATE posts SET moderation_status='BLOCKED',is_safe=FALSE,moderation_reason='R2 storage unavailable' WHERE post_id=%s",(row['post_id'],))
                _unlink_local(row.get('media_path'));failures.append(('POST',row['post_id']))
        if hasattr(g,'littlenet_message_floor'):
            rows=fetch_all('SELECT child_message_id,media_path FROM child_messages WHERE sender_child_id=%s AND child_message_id>%s',(uid,int(g.littlenet_message_floor)))
            for row in rows:
                execute("UPDATE child_messages SET moderation_status='BLOCKED' WHERE child_message_id=%s",(row['child_message_id'],))
                _unlink_local(row.get('media_path'));failures.append(('MESSAGE',row['child_message_id']))

    if failures:
        try:
            from services.social import parent_notify
            parent_notify(uid,'MEDIA_STORAGE_BLOCKED','A media upload was blocked because secure R2 storage was unavailable.','/parent/safety/')
        except Exception:
            pass
        response.status_code=503
        response.set_data(json.dumps({'success':False,'error':'Secure R2 media storage failed; content was not published.'}))
        response.content_type='application/json'
    return response


@api_bp.before_app_request
def child_locked_onboarding_gate():
    """Keep a child out of normal Kids Mode until face + age quiz are complete."""
    if session.get('role')!='CHILD' or not session.get('user_id'):
        return None
    path=request.path
    allowed_prefixes=(
        '/static/','/uploads/','/logout','/face/enroll','/quiz/start','/quiz/submit',
        '/api/language','/set-language',
    )
    if any(path.startswith(p) for p in allowed_prefixes):
        return None
    uid=int(session['user_id'])
    face=fetch_one('SELECT 1 FROM face_profiles WHERE child_id=%s',(uid,))
    if not face:
        return redirect('/face/enroll/')
    try:
        from quiz.service import needs_onboarding_quiz
        if needs_onboarding_quiz(uid):
            return redirect('/quiz/start/?onboarding=1')
    except Exception:
        created=fetch_one("SELECT 1 FROM activity_logs WHERE child_id=%s AND activity_type='ACCOUNT_CREATED_BY_PARENT' LIMIT 1",(uid,))
        if created:
            return redirect('/quiz/start/?onboarding=1')
    return None


@api_bp.before_app_request
def verified_parent_child_creation_gate():
    """Create children directly under an already verified ACTIVE parent."""
    if request.method!='POST' or request.path.rstrip('/')!='/parent/create-child':
        return None
    if session.get('role')!='PARENT' or not session.get('user_id'):
        return redirect('/login/?mode=parent')
    try:
        from auth.child_provisioning import create_child_for_verified_parent
        child_id=create_child_for_verified_parent(int(session['user_id']),request.form)
        child=fetch_one('SELECT full_name,age FROM users WHERE user_id=%s',(child_id,)) or {'full_name':'Your child','age':''}
        return render_template(
            'approval_success.html',
            is_verified=True,
            title='Child account created safely',
            message=f"{child['full_name']}'s age-{child['age']} Kids Mode account is linked to your verified Parent account. On first login, LittleNet will require live face enrollment and the age-based onboarding quiz before Home or Reels can open.",
            button_url='/parent/dashboard/',
            button_text='Go to Parent Dashboard',
        )
    except ValueError as exc:
        return render_template('parent_create_child.html',error=str(exc)),400
    except Exception:
        return render_template('parent_create_child.html',error='Child account could not be created. Check duplicate username and required values.'),400


@api_bp.before_app_request
def parent_registration_email_gate():
    """Intercept standalone parent registration before the legacy direct route.

    Parent flow is locked to: email -> OTP -> live adult/liveness -> ACTIVE.
    """
    if request.method!='POST' or request.path.rstrip('/')!='/register-parent':
        return None
    try:
        from auth.parent_email_otp import begin_parent_registration
        result=begin_parent_registration(request.form)
    except ValueError as exc:
        return _registration_error(str(exc),400)
    except Exception:
        return _registration_error('Parent registration could not be completed. Please try again.',500)

    session.clear()
    session['pending_parent_user_id']=int(result['user_id'])
    session['pending_parent_email']=result['email']
    session['pending_parent_email_sent']=bool(result.get('email_sent'))
    session['pending_parent_email_verified']=False
    return redirect('/verify-parent-email/')


@api_bp.route('/verify-parent-email/',methods=['GET','POST'])
@limiter.limit('20 per minute')
@login_required
def verify_parent_email():
    user_id=session['pending_parent_user_id']
    email=session['pending_parent_email']

    if session.get('pending_parent_email_verified'):
        return redirect('/verify-parent-liveness/')

    error=None
    delivery_error=None
    if session.get('pending_parent_email_sent') is False:
        delivery_error='The verification email could not be delivered. Check the configured email service, then use Resend verification code.'

    if request.method=='POST':
        from auth.parent_email_otp import verify_parent_email_otp
        try:
            ok,error,user=verify_parent_email_otp(int(user_id),request.form.get('otp',''))
        except Exception:
            ok=False;error='Email verification is temporarily unavailable. Please try again.';user=None
        if ok and user:
            session['pending_parent_email_verified']=True
            return redirect('/verify-parent-liveness/')

    return render_template(
        'parent_email_verify.html',
        masked_email=_masked_email(email),
        error=error,
        delivery_error=delivery_error,
    )


@api_bp.route('/verify-parent-email/resend/',methods=['POST'])
@limiter.limit('3 per 15 minutes')
@login_required
def resend_parent_email():
    user_id=session['pending_parent_user_id']
    email=session['pending_parent_email']
    if session.get('pending_parent_email_verified'):
        return redirect('/verify-parent-liveness/')
    from auth.parent_email_otp import resend_parent_email_otp
    try:
        ok,error=resend_parent_email_otp(int(user_id))
    except Exception:
        ok=False;error='Could not resend the verification email. Please try again.'
    if ok:
        session['pending_parent_email_sent']=True
        return render_template(
            'parent_email_verify.html',
            masked_email=_masked_email(email),
            notice='A new 6-digit code was sent. The previous code is no longer valid.',
        )
    return render_template(
        'parent_email_verify.html',
        masked_email=_masked_email(email),
        error=error,
    ),503


@api_bp.route('/verify-parent-liveness/',methods=['GET','POST'])
@limiter.limit('15 per minute')
@login_required
def verify_parent_liveness():
    """Final parent activation gate: live camera anti-spoof + adult estimate."""
    if not session.get('pending_parent_email_verified'):
        return redirect('/verify-parent-email/')
    user_id=int(session['pending_parent_user_id'])
    email=session['pending_parent_email']
    user=fetch_one("SELECT * FROM users WHERE user_id=%s AND role='PARENT'",(user_id,))
    if not user:
        session.clear();return redirect('/register-parent/')
    if user.get('account_status')=='ACTIVE':
        session.clear();return redirect('/login/?mode=parent')

    error=None
    if request.method=='POST':
        raw=(request.form.get('selfie_data') or '').strip()
        if 'base64,' not in raw:
            error='Live camera capture is required.'
        else:
            path=None
            try:
                encoded=raw.split('base64,',1)[1]
                if len(encoded)>12_000_000:
                    raise ValueError('camera_image_too_large')
                data=base64.b64decode(encoded,validate=True)
                if len(data)<1000 or len(data)>8*1024*1024:
                    raise ValueError('invalid_camera_image')
                fd,path=tempfile.mkstemp(prefix='parent_live_',suffix='.jpg');os.close(fd)
                with open(path,'wb') as fh:fh.write(data)
                from safety.face_service import verify_adult_face
                result=verify_adult_face(path)
                if not result.get('is_adult'):
                    reason=result.get('reason') or 'adult_verification_failed'
                    error='Live adult verification failed. Use your real face in good lighting and blink naturally.' if 'liveness' in reason else 'Adult age verification did not pass.'
                else:
                    execute("UPDATE users SET account_status='ACTIVE' WHERE user_id=%s AND role='PARENT' AND account_status='PENDING_APPROVAL'",(user_id,))
                    execute("INSERT INTO login_activity(user_id,login_method,success) VALUES(%s,'EMAIL_OTP_LIVENESS',TRUE)",(user_id,))
                    active=fetch_one('SELECT * FROM users WHERE user_id=%s',(user_id,))
                    session.clear()
                    from auth.routes import _set_session
                    _set_session(active,'EMAIL_OTP_LIVENESS')
                    return redirect('/parent/dashboard/')
            except Exception:
                if not error:error='Live verification could not be completed. Camera and AI verification are required; there is no bypass.'
            finally:
                if path:
                    try:os.unlink(path)
                    except OSError:pass

    return render_template(
        'parent_liveness_verify.html',
        masked_email=_masked_email(email),
        parent=user,
        error=error,
    )


@api_bp.route('/api/login/',methods=['POST'])
@csrf.exempt
@limiter.limit('10 per minute')
def api_login():
    d=request.get_json(silent=True) or {}; u=login_user(d.get('email',''),d.get('password',''))
    if not u or u.get('account_status') != 'ACTIVE': return jsonify(success=False,message='Invalid credentials or account not active'),401
    session.clear(); session['user_id']=u['user_id'];session['role']=u['role'];session['full_name']=u['full_name']
    if u['role']=='CHILD': session['usage_session_key']=str(start_session(u['user_id'])['session_key'])
    return jsonify(success=True,role=u['role'],user_id=u['user_id'],full_name=u['full_name'],has_profile=profile_exists(u['user_id']) if u['role']=='CHILD' else True)


# Attach the canonical native Flutter JSON API to the already-registered API
# blueprint. Keeping this at module end avoids circular imports during blueprint
# construction while ensuring `/api/mobile/v1/*` exists in the real Flask app.
from mobile.api import register_mobile_api
from mobile.admin_api import register_mobile_admin_api

register_mobile_api(api_bp)
register_mobile_admin_api(api_bp)
