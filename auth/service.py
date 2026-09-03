import uuid, bcrypt
from database.connection import fetch_one, execute, get_db_connection
from mailg.send_email import send_email
from config import Config
from services.identity import validate_username,validate_name

def hash_password(password): return bcrypt.hashpw(password.encode(),bcrypt.gensalt()).decode()
def check_password(password,hashed): return bcrypt.checkpw(password.encode(),hashed.encode())

def register_child(form):
    username = (form.get('username') or '').strip()
    if not validate_username(username):
        raise ValueError('Username must be 3-30 characters (letters, numbers, underscores) and contain no inappropriate words.')
    full_name = (form.get('full_name') or '').strip()
    if not validate_name(full_name):
        raise ValueError('Full name must start with a letter and be at least 2 characters.')
    parent_name = (form.get('parent_name') or '').strip()
    if not validate_name(parent_name):
        raise ValueError('Parent name must start with a letter and be at least 2 characters.')
    try:
        age = int(form.get('age', '0'))
    except (TypeError, ValueError):
        raise ValueError('Age must be a valid number between 4 and 18.')
    if not 4 <= age <= 18:
        raise ValueError('Age must be between 4 and 18 for Kids Mode.')
    password = form.get('password', '')
    if len(password) < 8:
        raise ValueError('Password must be at least 8 characters long.')
    token = str(uuid.uuid4())
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO users(username,full_name,email,password_hash,role,age) VALUES(%s,%s,%s,%s,'CHILD',%s) RETURNING user_id""",
            (username, full_name, form['email'].strip().lower(), hash_password(password), age)
        )
        child_id = cur.fetchone()['user_id']
        cur.execute(
            """INSERT INTO parent_child_map(child_id,parent_name,parent_email,approval_token) VALUES(%s,%s,%s,%s)""",
            (child_id, parent_name, form['parent_email'].strip().lower(), token)
        )
        conn.commit()
    except Exception as exc:
        conn.rollback()
        err_msg = str(exc).lower()
        if 'unique' in err_msg or 'duplicate' in err_msg:
            if 'username' in err_msg:
                raise ValueError(f"The username '{username}' is already taken. Please choose another one.")
            if 'email' in err_msg:
                raise ValueError("An account with this email address already exists. Please log in.")
        raise ValueError(f"Database error: {exc}")
    finally:
        conn.close()
    link = f"{Config.BASE_URL.rstrip('/')}/approve/{token}/"
    send_email(form['parent_email'], 'LittleNet Parent Approval', f'<h2>LittleNet</h2><p>Approve {full_name}</p><a href="{link}">Approve child account</a>')
    return token

def approve_child_account(token):
    conn=get_db_connection()
    try:
        cur=conn.cursor();cur.execute('SELECT * FROM parent_child_map WHERE approval_token=%s AND approved=FALSE FOR UPDATE',(token,));row=cur.fetchone()
        if not row:conn.rollback();return None
        cur.execute("UPDATE users SET account_status='ACTIVE' WHERE user_id=%s AND account_status='PENDING_APPROVAL'",(row['child_id'],))
        cur.execute('UPDATE parent_child_map SET approved=TRUE,approved_at=NOW() WHERE map_id=%s',(row['map_id'],));conn.commit()
    except Exception:conn.rollback();raise
    finally:conn.close()
    link=f"{Config.BASE_URL.rstrip('/')}/register-parent/{token}/"
    send_email(row['parent_email'],'LittleNet Parent Setup',f'<a href="{link}">Create / link Parent Mode account</a>')
    return row

def register_parent_account(token,form):
    password=form.get('password','')
    if len(password)<8:return False,'weak_password'
    conn=get_db_connection()
    try:
        cur=conn.cursor();cur.execute('SELECT * FROM parent_child_map WHERE approval_token=%s AND approved=TRUE FOR UPDATE',(token,));mapping=cur.fetchone()
        if not mapping:conn.rollback();return False,'invalid_token'
        if mapping.get('parent_id'):
            # The one-time token has already completed its parent link.
            conn.rollback();return False,'already_linked'
        email=mapping['parent_email'].lower();cur.execute("SELECT * FROM users WHERE email=%s AND role='PARENT'",(email,));existing=cur.fetchone()
        if existing:
            if not check_password(password,existing['password_hash']):conn.rollback();return False,'wrong_existing_parent_password'
            parent_id=existing['user_id']
        else:
            cur.execute("INSERT INTO users(username,full_name,email,password_hash,role,account_status) VALUES(%s,%s,%s,%s,'PARENT','ACTIVE') RETURNING user_id",(email,mapping['parent_name'],email,hash_password(password)))
            parent_id=cur.fetchone()['user_id']
        cur.execute('UPDATE parent_child_map SET parent_id=%s WHERE map_id=%s AND parent_id IS NULL',(parent_id,mapping['map_id']))
        cur.execute("INSERT INTO parent_safety_settings(child_id,parent_id,safety_level) VALUES(%s,%s,'STRICT') ON CONFLICT(child_id) DO UPDATE SET parent_id=EXCLUDED.parent_id",(mapping['child_id'],parent_id))
        conn.commit();return True,None
    except Exception:conn.rollback();raise
    finally:conn.close()

def login_user(identifier, password):
    val = (identifier or '').strip()
    row = fetch_one('SELECT * FROM users WHERE LOWER(email)=%s OR LOWER(username)=%s', (val.lower(), val.lower()))
    if not row or not check_password(password, row['password_hash']):
        return None
    return row

def profile_exists(child_id): return bool(fetch_one('SELECT 1 FROM child_profiles WHERE child_id=%s',(child_id,)))

def register_parent_direct(form):
    """Create a standalone Parent Mode account for the parent-first PPT workflow."""
    if not validate_username(form.get('username')):raise ValueError('invalid_username')
    if not validate_name(form.get('full_name')):raise ValueError('invalid_full_name')
    password=form.get('password','')
    if len(password)<8:raise ValueError('weak_password')
    email=(form.get('email') or '').strip().lower()
    if '@' not in email:raise ValueError('invalid_email')
    return execute("""INSERT INTO users(username,full_name,email,password_hash,role,account_status)
      VALUES(%s,%s,%s,%s,'PARENT','ACTIVE') RETURNING user_id""",
      (form['username'].strip(),form['full_name'].strip(),email,hash_password(password)),returning=True)


def create_child_by_parent(parent_id,form):
    """Atomically create + approve a child from an authenticated Parent Mode account."""
    if not validate_username(form.get('username')):raise ValueError('invalid_username')
    if not validate_name(form.get('full_name')):raise ValueError('invalid_full_name')
    try:age=int(form.get('age'))
    except (TypeError,ValueError):raise ValueError('invalid_age')
    if not 4<=age<=18:raise ValueError('invalid_age')
    password=form.get('password','')
    if len(password)<8:raise ValueError('weak_password')
    email=(form.get('email') or '').strip().lower()
    if '@' not in email:raise ValueError('invalid_email')
    try:limit=int(form.get('daily_limit') or 60)
    except (TypeError,ValueError):raise ValueError('invalid_limit')
    if not 1<=limit<=1440:raise ValueError('invalid_limit')
    safety=(form.get('safety_level') or 'STRICT').upper()
    if safety not in {'STANDARD','STRICT','VERY_STRICT'}:raise ValueError('invalid_safety')
    parent=fetch_one("SELECT * FROM users WHERE user_id=%s AND role='PARENT' AND account_status='ACTIVE'",(parent_id,))
    if not parent:raise ValueError('invalid_parent')
    conn=get_db_connection()
    try:
        cur=conn.cursor()
        cur.execute("""INSERT INTO users(username,full_name,email,password_hash,role,age,account_status)
          VALUES(%s,%s,%s,%s,'CHILD',%s,'ACTIVE') RETURNING user_id""",
          (form['username'].strip(),form['full_name'].strip(),email,hash_password(password),age))
        child_id=cur.fetchone()['user_id']
        cur.execute("""INSERT INTO parent_child_map(child_id,parent_id,parent_name,parent_email,approved,approved_at)
          VALUES(%s,%s,%s,%s,TRUE,NOW())""",(child_id,parent_id,parent['full_name'],parent['email']))
        cur.execute("""INSERT INTO child_profiles(child_id,parent_id,full_name,date_of_birth,age,school_name,location,current_class,bio)
          VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s)""",(child_id,parent_id,form['full_name'].strip(),form.get('date_of_birth') or None,age,form.get('school_name'),form.get('location'),form.get('current_class'),form.get('bio')))
        cur.execute("INSERT INTO parent_safety_settings(child_id,parent_id,safety_level) VALUES(%s,%s,%s)",(child_id,parent_id,safety))
        cur.execute("INSERT INTO child_time_limits(child_id,daily_limit_minutes,strict_mode) VALUES(%s,%s,%s)",(child_id,limit,'strict_mode' in form))
        cur.execute("""INSERT INTO parent_control_settings(child_id,parent_id,allow_reels,allow_stories,allow_messaging,allow_posting,allow_discover,educational_only_feed)
          VALUES(%s,%s,%s,%s,%s,%s,%s,%s)""",(child_id,parent_id,'allow_reels' in form,'allow_stories' in form,'allow_messaging' in form,'allow_posting' in form,'allow_discover' in form,'educational_only_feed' in form))
        cur.execute("INSERT INTO activity_logs(child_id,activity_type,activity_data) VALUES(%s,'ACCOUNT_CREATED_BY_PARENT',%s::jsonb)",(child_id,'{"approved":true}'))
        conn.commit();return child_id
    except Exception:
        conn.rollback();raise
    finally:conn.close()
