import os, uuid
from flask import Blueprint,render_template,request,redirect,session,jsonify
from werkzeug.utils import secure_filename
from auth.service import register_child,approve_child_account,register_parent_account,register_parent_direct,login_user,profile_exists
from safety.face_service import enroll,verify
from services.usage import start_session,close_session
from database.connection import fetch_one
from extensions import limiter
from database.connection import execute
from decorators import child_required,login_required
from services.i18n import set_language, LANGUAGES

auth_bp=Blueprint('auth',__name__,template_folder='templates')

def _set_session(user,method='PASSWORD'):
    session.clear(); session.permanent=True; session['user_id']=user['user_id']; session['role']=user['role']; session['full_name']=user['full_name']; session['mode']='KIDS' if user['role']=='CHILD' else 'PARENT'
    execute('INSERT INTO login_activity(user_id,login_method,success) VALUES(%s,%s,TRUE)',(user['user_id'],method))
    if user['role']=='CHILD':
        us=start_session(user['user_id']); session['usage_session_key']=str(us['session_key'])

def _dest(user):
    if user['role']=='CHILD': return '/child/dashboard/' if profile_exists(user['user_id']) else '/child/create-profile/'
    if user['role']=='PARENT': return '/parent/dashboard/'
    return '/admin/'

@auth_bp.route('/')
def mode_select(): return render_template('mode_select.html')

@auth_bp.route('/login/',methods=['GET','POST'])
@limiter.limit('10 per minute')
def login():
    mode=request.args.get('mode','kids').lower()
    if request.method=='POST':
        user=login_user(request.form.get('email',''),request.form.get('password',''))
        wanted='CHILD' if request.form.get('mode','kids')=='kids' else 'PARENT'
        if not user or user['role']!=wanted: return render_template('login.html',mode=request.form.get('mode','kids'),error='Invalid credentials for this mode'),401
        _set_session(user); return redirect(_dest(user))
    return render_template('login.html',mode=mode)

@auth_bp.route('/register-child',methods=['GET','POST'])
@limiter.limit('5 per hour')
def register_page():
    if request.method=='POST':
        try: register_child(request.form); return render_template('registered.html')
        except Exception as exc: return render_template('child_register.html',error='Account could not be created. Check duplicate email/username and try again.'),400
    return render_template('child_register.html')

@auth_bp.route('/approve/<token>/',methods=['GET','POST'])
@limiter.limit('10 per minute')
def approve_child(token):
    pending=fetch_one('''SELECT m.child_id,u.full_name FROM parent_child_map m JOIN users u ON u.user_id=m.child_id
      WHERE m.approval_token=%s AND m.approved=FALSE''',(token,))
    if not pending:return ('Invalid or already used approval link',400)
    if request.method=='GET':return render_template('approve_confirm.html',token=token,child=pending)
    row=approve_child_account(token)
    return render_template('approved.html',token=token) if row else ('Invalid or already used approval link',400)

@auth_bp.route('/register-parent',methods=['GET','POST'])
@limiter.limit('5 per hour')
def register_parent_direct_page():
    if request.method=='POST':
        try:
            register_parent_direct(request.form)
            return redirect('/login/?mode=parent')
        except Exception:
            return render_template('parent_register_direct.html',error='Parent account could not be created. Check the details and try again.'),400
    return render_template('parent_register_direct.html')

@auth_bp.route('/register-parent/<token>/',methods=['GET','POST'])
@limiter.limit('10 per minute')
def register_parent(token):
    if request.method=='POST':
        ok,reason=register_parent_account(token,request.form)
        if ok:return render_template('parent_registered.html')
        return render_template('parent_register.html',token=token,error='Use the existing parent account password.' if reason=='wrong_existing_parent_password' else 'Invalid approval link'),400
    return render_template('parent_register.html',token=token)

@auth_bp.route('/face/enroll/',methods=['GET','POST'])
@child_required
def face_enroll():
    if session.get('role')!='CHILD':return redirect('/login/?mode=kids')
    if request.method=='POST':
        photo=request.files.get('photo')
        if not photo:return render_template('face_enroll.html',error='Take a clear selfie.'),400
        os.makedirs('uploads/faces',exist_ok=True); path=os.path.join('uploads/faces',f'enroll_{session["user_id"]}_{uuid.uuid4().hex}.jpg'); photo.save(path)
        try: enroll(session['user_id'],path); return redirect('/child/dashboard/')
        except Exception as exc: return render_template('face_enroll.html',error='Face enrollment failed. Use a live, well-lit face.'),400
        finally:
            try: os.remove(path)
            except OSError: pass
    return render_template('face_enroll.html')

@auth_bp.route('/face-login/',methods=['GET','POST'])
@limiter.limit('10 per minute')
def face_login():
    if request.method=='POST':
        email=request.form.get('email','').strip().lower(); photo=request.files.get('photo'); user=fetch_one("SELECT * FROM users WHERE email=%s AND role='CHILD' AND account_status='ACTIVE'",(email,))
        if not user or not photo:return render_template('face_login.html',error='Child account/photo not found.'),400
        os.makedirs('uploads/faces',exist_ok=True); path=os.path.join('uploads/faces',f'login_{uuid.uuid4().hex}.jpg'); photo.save(path)
        try:
            ok,reason,_=verify(user['user_id'],path)
            if not ok:return render_template('face_login.html',error='Liveness failed.' if reason=='liveness_failed' else 'Face did not match.'),401
            _set_session(user,'FACE'); return redirect(_dest(user))
        except Exception:return render_template('face_login.html',error='Face service unavailable. Use password login.'),503
        finally:
            try: os.remove(path)
            except OSError: pass
    return render_template('face_login.html')

@auth_bp.route('/logout/',methods=['POST'])
@login_required
def logout():
    if session.get('usage_session_key'): close_session(session['usage_session_key'])
    session.clear(); return redirect('/')

@auth_bp.route('/switch-mode/',methods=['POST'])
@login_required
def switch_mode():
    if session.get('usage_session_key'): close_session(session['usage_session_key'])
    session.clear(); return redirect('/')


@auth_bp.route('/admin-login/',methods=['GET','POST'])
@limiter.limit('10 per minute')
def admin_login():
    if request.method=='POST':
        user=login_user(request.form.get('email',''),request.form.get('password',''))
        if not user or user['role']!='ADMIN':return render_template('login.html',mode='admin',error='Invalid admin credentials'),401
        _set_session(user);return redirect('/admin/')
    return render_template('login.html',mode='admin')

@auth_bp.route('/language/',methods=['POST'])
@login_required
def change_language():
    lang=set_language(session['user_id'],request.form.get('language','EN'))
    session['language']=lang
    return redirect(request.referrer or ('/parent/dashboard/' if session.get('role')=='PARENT' else '/child/dashboard/'))
