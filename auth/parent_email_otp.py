"""Email OTP gate for standalone Parent Mode registration.

The parent account is created in PENDING_APPROVAL state. Email OTP proves email
ownership only; the account remains pending until live adult/liveness verification
succeeds. OTP values are never stored in plaintext and expire after ten minutes.
"""
import hashlib
import hmac
import secrets
from datetime import date, datetime

from auth.service import hash_password
from config import Config
from database.connection import get_db_connection, fetch_one
from mailg.send_email import send_email
from services.identity import validate_name, validate_username

OTP_TTL_MINUTES = 10
OTP_MAX_ATTEMPTS = 5


def _ensure_table():
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS parent_email_otps (
                    user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
                    code_hash TEXT NOT NULL,
                    expires_at TIMESTAMP NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
                    sent_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    verified_at TIMESTAMP
                )
                """
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _otp_hash(user_id, code):
    secret = str(Config.SECRET_KEY or '')
    payload = f"parent-email-otp:{user_id}:{code}:{secret}".encode('utf-8')
    return hashlib.sha256(payload).hexdigest()


def _new_code():
    return f"{secrets.randbelow(1_000_000):06d}"


def _adult_age(dob_str):
    try:
        born = datetime.strptime((dob_str or '')[:10], '%Y-%m-%d').date()
    except (TypeError, ValueError):
        raise ValueError('Please provide a valid date of birth.')
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def _validate_registration(form):
    username = (form.get('username') or '').strip()
    full_name = (form.get('full_name') or '').strip()
    email = (form.get('email') or '').strip().lower()
    password = form.get('password') or ''
    dob_str = (form.get('dob') or form.get('date_of_birth') or '').strip()

    if not validate_username(username):
        raise ValueError('Username must be 3-30 safe characters.')
    if not validate_name(full_name):
        raise ValueError('Please enter a valid parent or guardian name.')
    if '@' not in email or email.startswith('@') or email.endswith('@'):
        raise ValueError('Please enter a valid email address.')
    if len(password) < 8:
        raise ValueError('Password must be at least 8 characters long.')
    if _adult_age(dob_str) < 18:
        raise ValueError('Adult verification failed: Parent must be 18 years of age or older.')
    if form.get('guardian_declaration') != '1':
        raise ValueError('Please confirm the adult guardian declaration.')

    # Deliberately no arithmetic/captcha-style guardian question here. Adult
    # status is proved by DOB validation, email ownership and the required live
    # camera liveness/adult gate that follows OTP verification.
    return username, full_name, email, password, dob_str


def _send_code(user_id, email, full_name, code):
    body = f"""
    <h2>Verify your LittleNet Parent Account</h2>
    <p>Hello <strong>{full_name}</strong>,</p>
    <p>Your one-time verification code is:</p>
    <p style="font-size:30px;font-weight:800;letter-spacing:8px;margin:20px 0;">{code}</p>
    <p>This code expires in {OTP_TTL_MINUTES} minutes. Do not share it with anyone.</p>
    <p>After OTP verification, LittleNet will ask for a live adult/liveness check before the account can become active.</p>
    <p>If you did not create a LittleNet Parent account, you can ignore this email.</p>
    """
    return bool(send_email(email, 'LittleNet: Your 6-digit parent verification code', body))


def begin_parent_registration(form):
    """Create a pending parent account and send its first OTP."""
    _ensure_table()
    username, full_name, email, password, dob_str = _validate_registration(form)
    code = _new_code()

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT user_id, username, email, role, account_status FROM users WHERE LOWER(username)=LOWER(%s) OR LOWER(email)=LOWER(%s) LIMIT 1",
                (username, email),
            )
            existing = cur.fetchone()
            if existing:
                if (existing.get('username') or '').casefold() == username.casefold():
                    raise ValueError(f"The username '{username}' already exists. Please choose a different username.")
                raise ValueError(f"The email '{email}' is already used by a LittleNet account. Please log in instead.")

            cur.execute(
                """
                INSERT INTO users(username,full_name,email,password_hash,role,dob,account_status)
                VALUES(%s,%s,%s,%s,'PARENT',%s,'PENDING_APPROVAL')
                RETURNING user_id
                """,
                (username, full_name, email, hash_password(password), dob_str),
            )
            user_id = cur.fetchone()['user_id']
            cur.execute(
                """
                INSERT INTO parent_email_otps(user_id,code_hash,expires_at,attempts,sent_at,verified_at)
                VALUES(%s,%s,NOW() + INTERVAL '10 minutes',0,NOW(),NULL)
                ON CONFLICT(user_id) DO UPDATE SET
                    code_hash=EXCLUDED.code_hash,
                    expires_at=EXCLUDED.expires_at,
                    attempts=0,
                    sent_at=NOW(),
                    verified_at=NULL
                """,
                (user_id, _otp_hash(user_id, code)),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    sent = _send_code(user_id, email, full_name, code)
    return {'user_id': user_id, 'email': email, 'full_name': full_name, 'email_sent': sent}


def verify_parent_email_otp(user_id, code):
    """Verify email ownership but deliberately keep the parent account pending."""
    _ensure_table()
    code = (code or '').strip()
    if len(code) != 6 or not code.isdigit():
        return False, 'Enter the 6-digit code from your email.', None

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT o.code_hash,o.expires_at,o.attempts,o.verified_at,
                       u.user_id,u.email,u.full_name,u.role,u.account_status
                FROM parent_email_otps o
                JOIN users u ON u.user_id=o.user_id
                WHERE o.user_id=%s
                FOR UPDATE
                """,
                (user_id,),
            )
            row = cur.fetchone()
            if not row or row.get('role') != 'PARENT':
                conn.rollback()
                return False, 'Verification request not found. Please register again.', None
            if row.get('verified_at'):
                conn.commit()
                return True, None, fetch_one('SELECT * FROM users WHERE user_id=%s', (user_id,))
            if row['attempts'] >= OTP_MAX_ATTEMPTS:
                conn.rollback()
                return False, 'Too many incorrect attempts. Request a new code.', None
            cur.execute('SELECT NOW() AS now')
            now = cur.fetchone()['now']
            expires_at = row['expires_at']
            if getattr(expires_at, 'tzinfo', None) is None and getattr(now, 'tzinfo', None) is not None:
                expires_at = expires_at.replace(tzinfo=now.tzinfo)
            if now > expires_at:
                conn.rollback()
                return False, 'That code has expired. Request a new code.', None

            if not hmac.compare_digest(row['code_hash'], _otp_hash(user_id, code)):
                cur.execute('UPDATE parent_email_otps SET attempts=attempts+1 WHERE user_id=%s', (user_id,))
                conn.commit()
                return False, 'Incorrect verification code.', None

            cur.execute('UPDATE parent_email_otps SET verified_at=NOW() WHERE user_id=%s', (user_id,))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    user = fetch_one('SELECT * FROM users WHERE user_id=%s', (user_id,))
    return True, None, user


def resend_parent_email_otp(user_id):
    """Rotate the code for a parent who has not yet completed email verification."""
    _ensure_table()
    user = fetch_one(
        """SELECT u.user_id,u.email,u.full_name,u.role,u.account_status,o.verified_at
           FROM users u LEFT JOIN parent_email_otps o ON o.user_id=u.user_id
           WHERE u.user_id=%s""",
        (user_id,),
    )
    if not user or user.get('role') != 'PARENT' or user.get('account_status') == 'ACTIVE':
        return False, 'No pending parent verification was found.'
    if user.get('verified_at'):
        return False, 'Email is already verified. Continue with live adult verification.'

    code = _new_code()
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO parent_email_otps(user_id,code_hash,expires_at,attempts,sent_at,verified_at)
                VALUES(%s,%s,NOW() + INTERVAL '10 minutes',0,NOW(),NULL)
                ON CONFLICT(user_id) DO UPDATE SET
                    code_hash=EXCLUDED.code_hash,
                    expires_at=EXCLUDED.expires_at,
                    attempts=0,
                    sent_at=NOW(),
                    verified_at=NULL
                """,
                (user_id, _otp_hash(user_id, code)),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    if not _send_code(user_id, user['email'], user['full_name'], code):
        if os.getenv('RESEND_API_KEY'):
            return False, 'Email delivery failed. In Resend testing mode, use the account email (littlenet655@gmail.com) or verify your domain in Resend.'
        return False, 'Email delivery is unavailable. Check SMTP configuration and try again.'
    return True, None

