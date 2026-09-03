import os, uuid, base64
from flask import Blueprint, render_template, request, redirect, session, jsonify, flash, url_for
from werkzeug.utils import secure_filename
from auth.service import (
    register_child,
    approve_child_account,
    register_parent_account,
    register_parent_direct,
    login_user,
    profile_exists,
    get_parent_verification_data,
    process_parent_verification,
    get_child_approval_details,
    process_child_decision
)
from safety.face_service import enroll, verify
from services.usage import start_session, close_session
from database.connection import fetch_one, execute
from extensions import limiter, csrf
from decorators import child_required, login_required
from services.i18n import set_language, LANGUAGES

auth_bp = Blueprint('auth', __name__, template_folder='templates')

def _set_session(user, method='PASSWORD'):
    session.clear()
    session.permanent = True
    session['user_id'] = user['user_id']
    session['role'] = user['role']
    session['full_name'] = user['full_name']
    session['mode'] = 'KIDS' if user['role'] == 'CHILD' else 'PARENT'
    execute('INSERT INTO login_activity(user_id,login_method,success) VALUES(%s,%s,TRUE)', (user['user_id'], method))
    if user['role'] == 'CHILD':
        us = start_session(user['user_id'])
        session['usage_session_key'] = str(us['session_key'])

def _dest(user):
    if user['role'] == 'CHILD':
        return '/child/dashboard/' if profile_exists(user['user_id']) else '/child/create-profile/'
    if user['role'] == 'PARENT':
        return '/parent/dashboard/'
    return '/admin/'

@auth_bp.route('/')
def mode_select():
    if session.get('user_id'):
        if session.get('role') == 'CHILD':
            return redirect('/child/dashboard/' if profile_exists(session['user_id']) else '/child/create-profile/')
        elif session.get('role') == 'PARENT':
            return redirect('/parent/dashboard/')
        elif session.get('role') == 'ADMIN':
            return redirect('/admin/')
    mode = request.args.get('mode', 'kids').lower()
    return render_template('login.html', mode=mode)

@auth_bp.route('/login/', methods=['GET', 'POST'])
@limiter.limit('30 per minute')
def login():
    mode = request.args.get('mode', 'kids').lower()
    if request.method == 'POST':
        ident = request.form.get('email', '') or request.form.get('username', '')
        user = login_user(ident, request.form.get('password', ''))
        wanted = 'CHILD' if request.form.get('mode', 'kids') == 'kids' else 'PARENT'
        if not user or user['role'] != wanted:
            return render_template('login.html', mode=request.form.get('mode', 'kids'), error='Invalid username/email or password for this mode'), 401
        if user['account_status'] == 'PENDING_APPROVAL':
            mapping = fetch_one('SELECT approval_token, verification_token FROM parent_child_map WHERE child_id=%s', (user['user_id'],))
            tok = mapping['verification_token'] if mapping and mapping.get('verification_token') else (mapping['approval_token'] if mapping else None)
            return render_template('login.html', mode=request.form.get('mode', 'kids'),
                                   error='This child account is waiting for parent identity verification & approval.',
                                   approval_token=tok), 403
        if user['account_status'] != 'ACTIVE':
            return render_template('login.html', mode=request.form.get('mode', 'kids'), error='Account is suspended or inactive.'), 403
        _set_session(user)
        return redirect(_dest(user))
    return render_template('login.html', mode=mode)

@auth_bp.route('/register-child', methods=['GET', 'POST'])
@auth_bp.route('/register-child/', methods=['GET', 'POST'])
@limiter.limit('100 per hour')
def register_page():
    if request.method == 'POST':
        res = register_child(request.form)
        if not res.get("success"):
            return render_template('child_register.html', error=res.get("error", "Registration failed")), 400
        
        token = res.get("verification_token") or res.get("approval_token") or res.get("token")
        
        # Instant demo mode shortcut if requested
        if request.form.get('instant_demo') == '1':
            approve_child_account(token)
            child_user = fetch_one('SELECT * FROM users WHERE LOWER(username)=%s', (request.form.get('username', '').strip().lower(),))
            if child_user:
                _set_session(child_user)
                return redirect(_dest(child_user))

        return render_template(
            'registered.html',
            token=token,
            parent_email=request.form.get('parent_email'),
            child_name=res.get("child_name")
        )
    return render_template('child_register.html')

@auth_bp.route('/verify-parent/<token>/', methods=['GET', 'POST'])
@limiter.limit('30 per minute')
def verify_parent(token):
    child_data = get_parent_verification_data(token)
    if not child_data:
        return render_template(
            "approval_success.html",
            is_error=True,
            title="Invalid Verification Link",
            message="This parent identity verification link is invalid or has expired.",
            button_url="/login/",
            button_text="Go to Login"
        ), 404

    # If child is already approved, show success rather than an error
    if child_data.get("approved"):
        return render_template(
            "approval_success.html",
            is_verified=True,
            title="Account Already Approved!",
            message=f"The account for {child_data.get('child_name')} has already been verified and is active.",
            button_url="/login/?mode=kids",
            button_text="Go to Child Login"
        )

    # Check if parent account already exists
    parent_user = fetch_one("SELECT user_id FROM users WHERE LOWER(email)=%s AND role='PARENT'", (child_data["parent_email"].lower(),))
    parent_exists = bool(parent_user)

    if request.method == "POST":
        selfie_b64 = request.form.get("selfie_data", "")
        selfie_bytes = b""
        if selfie_b64 and "base64," in selfie_b64:
            try:
                selfie_bytes = base64.b64decode(selfie_b64.split("base64,")[1])
            except Exception as e:
                print("[SELFIE DECODE ERROR]", e)

        result = process_parent_verification(token, request.form, selfie_bytes)
        if not result.get("success"):
            return render_template(
                "parent_verify.html",
                child=child_data,
                parent_exists=parent_exists,
                error=result.get("error")
            ), 400

        # Auto-login newly verified parent into session
        parent_row = fetch_one("SELECT * FROM users WHERE user_id=%s", (result["parent_id"],))
        if parent_row:
            _set_session(parent_row)

        return redirect(f"/parent/approve-child/{result['approval_token']}/")

    return render_template("parent_verify.html", child=child_data, parent_exists=parent_exists)

@auth_bp.route('/parent/approve-child/<token>/', methods=['GET', 'POST'])
@limiter.limit('30 per minute')
def parent_approve_child(token):
    # Require authentication as PARENT
    if 'user_id' not in session or session.get('role') != 'PARENT':
        return redirect(f"/login/?mode=parent&next=/parent/approve-child/{token}/")

    logged_in_parent_id = session['user_id']
    check = get_child_approval_details(token, logged_in_parent_id)

    if request.method == "POST":
        if not check.get("valid"):
            reason = check.get("reason", "UNKNOWN")
            if reason == "TOKEN_ALREADY_USED":
                return render_template(
                    "approval_success.html",
                    is_verified=True,
                    title="Account Already Approved!",
                    message="This child account has already been approved and is fully active.",
                    button_url="/parent/dashboard/",
                    button_text="Go to Parent Dashboard"
                )
            return render_template(
                "approval_success.html",
                is_error=True,
                title="Action Failed",
                message=f"Cannot process request: {reason}",
                button_url="/parent/dashboard/",
                button_text="Go to Parent Dashboard"
            ), 403

        decision = request.form.get("decision", "APPROVE")
        rejection_reason = request.form.get("rejection_reason")
        result = process_child_decision(token, logged_in_parent_id, decision, rejection_reason)

        if result.get("success"):
            if result.get("action") == "APPROVED":
                return render_template(
                    "approval_success.html",
                    is_verified=True,
                    title="Child Account Approved!",
                    message=f"You have successfully verified and activated {result.get('child_name')}'s account. Your parental supervision controls are now active.",
                    button_url="/parent/dashboard/",
                    button_text="Go to Parent Dashboard"
                )
            else:
                return render_template(
                    "approval_success.html",
                    is_error=True,
                    title="Account Declined",
                    message=f"You have declined the registration request for {result.get('child_name')}.",
                    button_url="/parent/dashboard/",
                    button_text="Go to Parent Dashboard"
                )
        return render_template(
            "approval_success.html",
            is_error=True,
            title="Approval Failed",
            message=result.get("error", "An unknown error occurred."),
            button_url="/parent/dashboard/",
            button_text="Go to Parent Dashboard"
        ), 400

    # GET request
    if not check.get("valid"):
        reason = check.get("reason", "UNKNOWN")
        if reason == "TOKEN_ALREADY_USED":
            return render_template(
                "approval_success.html",
                is_verified=True,
                title="Account Already Approved!",
                message="This child account has already been approved and is active.",
                button_url="/parent/dashboard/",
                button_text="Go to Parent Dashboard"
            )
        return render_template(
            "approval_success.html",
            is_error=True,
            title="Invalid or Expired Link",
            message=f"This approval request cannot be opened: {reason}",
            button_url="/parent/dashboard/",
            button_text="Go to Parent Dashboard"
        ), 400

    return render_template(
        "approve_child.html",
        valid=True,
        child=check["child"],
        parent=check["parent"],
        verification=check.get("verification", {"status": "VERIFIED", "masked_id": "XXXX-XXXX-5678"}),
        token=token
    )

@auth_bp.route('/approve/<token>/',methods=['GET','POST'])
@limiter.limit('30 per minute')
def approve_child(token):
    pending = fetch_one('''SELECT m.child_id,u.full_name FROM parent_child_map m JOIN users u ON u.user_id=m.child_id
      WHERE (m.approval_token=%s OR m.verification_token=%s) AND m.approved=FALSE''', (token, token))
    if not pending:
        already = fetch_one('''SELECT m.child_id,u.full_name FROM parent_child_map m JOIN users u ON u.user_id=m.child_id
          WHERE (m.approval_token=%s OR m.verification_token=%s) AND m.approved=TRUE''', (token, token))
        if already:
            flash(f"Account for {already['full_name']} is already approved and ready to log in!", "success")
            return redirect(url_for('auth.login', mode='kids'))
        return ('Invalid or expired approval link', 400)
    if request.method=='GET':return render_template('approve_confirm.html',token=token,child=pending)
    row=approve_child_account(token)
    return render_template('approved.html',token=token) if row else ('Invalid or already used approval link',400)

@auth_bp.route('/register-parent', methods=['GET', 'POST'])
@auth_bp.route('/register-parent/', methods=['GET', 'POST'])
@limiter.limit('100 per hour')
def register_parent_direct_page():
    if request.method == 'POST':
        try:
            res = register_parent_direct(request.form)
            uid = res['user_id']
            user = fetch_one('SELECT * FROM users WHERE user_id=%s', (uid,))
            _set_session(user)
            return redirect('/parent/dashboard/')
        except Exception as exc:
            return render_template('parent_register_direct.html', error=str(exc)), 400
    return render_template('parent_register_direct.html')

@auth_bp.route('/register-parent/<token>/', methods=['GET', 'POST'])
@limiter.limit('10 per minute')
def register_parent(token):
    return redirect(f"/verify-parent/{token}/")

@auth_bp.route('/face/enroll/', methods=['GET', 'POST'])
@child_required
def face_enroll():
    if session.get('role') != 'CHILD':
        return redirect('/login/?mode=kids')
    if request.method == 'POST':
        photo = request.files.get('photo')
        if not photo:
            return render_template('face_enroll.html', error='Take a clear selfie.'), 400
        os.makedirs('uploads/faces', exist_ok=True)
        path = os.path.join('uploads/faces', f'enroll_{session["user_id"]}_{uuid.uuid4().hex}.jpg')
        photo.save(path)
        try:
            enroll(session['user_id'], path)
            return redirect('/child/dashboard/')
        except Exception:
            return render_template('face_enroll.html', error='Face enrollment failed. Use a live, well-lit face.'), 400
        finally:
            try:
                os.remove(path)
            except OSError:
                pass
    return render_template('face_enroll.html')

@auth_bp.route('/face-login/', methods=['GET', 'POST'])
@limiter.limit('10 per minute')
def face_login():
    if request.method == 'POST':
        email = request.form.get('email', '').strip().lower()
        photo = request.files.get('photo')
        user = fetch_one("SELECT * FROM users WHERE email=%s AND role='CHILD' AND account_status='ACTIVE'", (email,))
        if not user or not photo:
            return render_template('face_login.html', error='Child account/photo not found.'), 400
        os.makedirs('uploads/faces', exist_ok=True)
        path = os.path.join('uploads/faces', f'login_{uuid.uuid4().hex}.jpg')
        photo.save(path)
        try:
            ok, reason, _ = verify(user['user_id'], path)
            if not ok:
                return render_template('face_login.html', error='Liveness failed.' if reason == 'liveness_failed' else 'Face did not match.'), 401
            _set_session(user, 'FACE')
            return redirect(_dest(user))
        except Exception:
            return render_template('face_login.html', error='Face service unavailable. Use password login.'), 503
        finally:
            try:
                os.remove(path)
            except OSError:
                pass
    return render_template('face_login.html')

@auth_bp.route('/logout/',methods=['POST'])
def logout():
    if session.get('usage_session_key'):
        close_session(session['usage_session_key'])
    session.clear()
    return redirect('/')

@auth_bp.route('/switch-mode/',methods=['POST'])
def switch_mode():
    if session.get('usage_session_key'):
        close_session(session['usage_session_key'])
    session.clear()
    return redirect('/')

@auth_bp.route('/admin-login/', methods=['GET', 'POST'])
@limiter.limit('10 per minute')
def admin_login():
    if request.method == 'POST':
        user = login_user(request.form.get('email', ''), request.form.get('password', ''))
        if not user or user['role'] != 'ADMIN':
            return render_template('login.html', mode='admin', error='Invalid admin credentials'), 401
        _set_session(user)
        return redirect('/admin/')
    return render_template('login.html', mode='admin')

@auth_bp.route('/language/', methods=['POST'])
@login_required
def change_language():
    lang = set_language(session['user_id'], request.form.get('language', 'EN'))
    session['language'] = lang
    return redirect(request.referrer or ('/parent/dashboard/' if session.get('role') == 'PARENT' else '/child/dashboard/'))
