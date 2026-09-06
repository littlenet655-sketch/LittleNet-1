import random

from flask import Blueprint,request,jsonify,session,render_template,redirect
from extensions import csrf,limiter
from auth.service import login_user,profile_exists
from services.usage import start_session

api_bp=Blueprint('api',__name__)


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


@api_bp.before_app_request
def parent_registration_email_gate():
    """Intercept standalone parent registration before the legacy direct route.

    GET /register-parent/ still uses the original UI. Its POST is handled here so
    the parent cannot be logged in until email ownership is verified by OTP.
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
    return redirect('/verify-parent-email/')


@api_bp.route('/verify-parent-email/',methods=['GET','POST'])
@limiter.limit('20 per minute')
def verify_parent_email():
    user_id=session.get('pending_parent_user_id')
    email=session.get('pending_parent_email')
    if not user_id or not email:
        return redirect('/register-parent/')

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
            session.clear()
            from auth.routes import _set_session
            _set_session(user,'EMAIL_OTP')
            return redirect('/parent/dashboard/')

    return render_template(
        'parent_email_verify.html',
        masked_email=_masked_email(email),
        error=error,
        delivery_error=delivery_error,
    )


@api_bp.route('/verify-parent-email/resend/',methods=['POST'])
@limiter.limit('3 per 15 minutes')
def resend_parent_email():
    user_id=session.get('pending_parent_user_id')
    email=session.get('pending_parent_email')
    if not user_id or not email:
        return redirect('/register-parent/')
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


@api_bp.route('/api/login/',methods=['POST'])
@csrf.exempt
@limiter.limit('10 per minute')
def api_login():
    d=request.get_json(silent=True) or {}; u=login_user(d.get('email',''),d.get('password',''))
    if not u or u.get('account_status') != 'ACTIVE': return jsonify(success=False,message='Invalid credentials or account not active'),401
    session.clear(); session['user_id']=u['user_id'];session['role']=u['role'];session['full_name']=u['full_name']
    if u['role']=='CHILD': session['usage_session_key']=str(start_session(u['user_id'])['session_key'])
    return jsonify(success=True,role=u['role'],user_id=u['user_id'],full_name=u['full_name'],has_profile=profile_exists(u['user_id']) if u['role']=='CHILD' else True)
