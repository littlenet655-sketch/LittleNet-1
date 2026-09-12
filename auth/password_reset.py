"""Password Reset Service for LittleNet.

Supports:
1. Requesting password reset OTP via registered email for Parents or Kids.
2. For Kids without personal emails, routing OTP to verified linked parent.
3. Verification of 6-digit OTP code and bcrypt updating of password.
4. Direct parent reset of child's password from Parent Controls.
"""
import hashlib
import hmac
import re
import secrets
from datetime import datetime

import bcrypt

from config import Config
from database.connection import get_db_connection, fetch_one, execute
from mailg.send_email import send_email

OTP_TTL_MINUTES = 15
OTP_MAX_ATTEMPTS = 5


def _ensure_table():
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS password_reset_otps (
                    user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
                    code_hash TEXT NOT NULL,
                    expires_at TIMESTAMP NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
                    sent_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    secret = str(Config.SECRET_KEY or "littlenet-default-secret")
    payload = f"pwd-reset:{user_id}:{code}:{secret}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _mask_email(email: str) -> str:
    if not email or "@" not in email:
        return "your registered email"
    user_part, domain = email.split("@", 1)
    if len(user_part) <= 2:
        masked_user = user_part[0] + "*"
    else:
        masked_user = user_part[0] + ("*" * (len(user_part) - 2)) + user_part[-1]
    return f"{masked_user}@{domain}"


def request_password_reset(identifier: str):
    """Request a password reset OTP for a username or email."""
    _ensure_table()
    ident = (identifier or "").strip()
    if not ident:
        return False, "Please enter your username or email.", None

    user = fetch_one(
        """
        SELECT user_id, username, full_name, email, role, account_status
        FROM users
        WHERE LOWER(email) = LOWER(%s) OR LOWER(username) = LOWER(%s)
        LIMIT 1
        """,
        (ident, ident),
    )
    if not user:
        return False, "No LittleNet account found matching that username or email.", None

    if user.get("account_status") == "SUSPENDED":
        return False, "This account is suspended. Please contact safety support.", None

    # Determine recipient email
    target_email = (user.get("email") or "").strip()
    is_parent_proxy = False

    # For any child account or accounts with placeholder emails, route OTP to the verified parent
    if user.get("role") == "CHILD" or not target_email or "@" not in target_email or target_email.endswith(".internal") or target_email.endswith("@littlenet.local"):
        parent_map = fetch_one(
            """
            SELECT pcm.parent_email, u.email AS parent_user_email, u.full_name AS parent_name
            FROM parent_child_map pcm
            LEFT JOIN users u ON u.user_id = pcm.parent_id
            WHERE pcm.child_id = %s AND (pcm.approved = TRUE OR pcm.approval_status = 'APPROVED')
            ORDER BY pcm.map_id DESC LIMIT 1
            """,
            (user["user_id"],),
        )
        if parent_map:
            target_email = (parent_map.get("parent_user_email") or parent_map.get("parent_email") or "").strip()
            is_parent_proxy = True


    if not target_email or "@" not in target_email:
        if user.get("role") == "CHILD":
            return False, "No parent email found for this child account. Ask your parent to reset your password from Parent Mode.", None
        return False, "No valid email address registered for this account.", None

    code = f"{secrets.randbelow(1_000_000):06d}"
    code_hash = _otp_hash(user["user_id"], code)

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO password_reset_otps (user_id, code_hash, expires_at, attempts, sent_at)
                VALUES (%s, %s, NOW() + INTERVAL '15 minutes', 0, NOW())
                ON CONFLICT (user_id) DO UPDATE SET
                    code_hash = EXCLUDED.code_hash,
                    expires_at = EXCLUDED.expires_at,
                    attempts = 0,
                    sent_at = NOW()
                """,
                (user["user_id"], code_hash),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    # Compose email
    subject = "LittleNet Password Reset Verification Code"
    if is_parent_proxy:
        body = f"""
        <div style="font-family: Arial, sans-serif; max-width: 540px; margin: 0 auto; padding: 24px; border: 1px solid #E2E8F0; border-radius: 12px;">
          <h2 style="color: #0095F6; margin-top: 0;">LittleNet Safety Alert & Password Reset</h2>
          <p>Hello,</p>
          <p>A password reset was requested for your child's account: <b>@{user['username']}</b> ({user['full_name']}).</p>
          <p>Please enter the following 6-digit verification code in the LittleNet app:</p>
          <div style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #1E293B; background: #F1F5F9; padding: 16px; text-align: center; border-radius: 8px; margin: 20px 0;">
            {code}
          </div>
          <p style="color: #64748B; font-size: 13px;">This code will expire in 15 minutes. If you or your child did not request this, you can safely ignore this email or review child activity in Parent Mode.</p>
        </div>
        """
    else:
        body = f"""
        <div style="font-family: Arial, sans-serif; max-width: 540px; margin: 0 auto; padding: 24px; border: 1px solid #E2E8F0; border-radius: 12px;">
          <h2 style="color: #0095F6; margin-top: 0;">LittleNet Password Reset</h2>
          <p>Hello {user['full_name']},</p>
          <p>You requested to reset your LittleNet password. Enter the verification code below in the app:</p>
          <div style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #1E293B; background: #F1F5F9; padding: 16px; text-align: center; border-radius: 8px; margin: 20px 0;">
            {code}
          </div>
          <p style="color: #64748B; font-size: 13px;">This code will expire in 15 minutes. If you did not request a password reset, please secure your account immediately.</p>
        </div>
        """

    sent = send_email(target_email, subject, body)

    return True, None, {
        "user_id": user["user_id"],
        "username": user["username"],
        "masked_email": _mask_email(target_email),
        "is_parent_proxy": is_parent_proxy,
        "email_sent": bool(sent),
    }


def verify_and_reset_password(user_id: int, code: str, new_password: str):
    """Verify OTP and set new password."""
    _ensure_table()
    code = (code or "").strip()
    if len(code) != 6 or not code.isdigit():
        return False, "Please enter the 6-digit verification code sent to your email."

    new_pwd = (new_password or "").strip()
    if len(new_pwd) < 8:
        return False, "New password must be at least 8 characters long."

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT code_hash, expires_at, attempts
                FROM password_reset_otps
                WHERE user_id = %s
                FOR UPDATE
                """,
                (user_id,),
            )
            row = cur.fetchone()
            if not row:
                conn.rollback()
                return False, "No active password reset request found. Please request a new code."

            if row["attempts"] >= OTP_MAX_ATTEMPTS:
                conn.rollback()
                return False, "Too many incorrect attempts. Please request a new reset code."

            cur.execute("SELECT NOW() AS now")
            now = cur.fetchone()["now"]
            expires_at = row["expires_at"]
            if getattr(expires_at, "tzinfo", None) is None and getattr(now, "tzinfo", None) is not None:
                expires_at = expires_at.replace(tzinfo=now.tzinfo)
            if now > expires_at:
                conn.rollback()
                return False, "The verification code has expired. Please request a new one."

            if not hmac.compare_digest(row["code_hash"], _otp_hash(user_id, code)):
                cur.execute("UPDATE password_reset_otps SET attempts = attempts + 1 WHERE user_id = %s", (user_id,))
                conn.commit()
                return False, "Incorrect verification code. Please check your email and try again."

            # Code valid: update password hash
            new_hash = bcrypt.hashpw(new_pwd.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
            cur.execute("UPDATE users SET password_hash = %s WHERE user_id = %s", (new_hash, user_id))
            cur.execute("DELETE FROM password_reset_otps WHERE user_id = %s", (user_id,))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return True, "Password reset successfully. You can now sign in with your new password."


def parent_reset_child_password(parent_id: int, child_id: int, new_password: str):
    """Allows an authenticated parent to directly reset their linked child's password."""
    new_pwd = (new_password or "").strip()
    if len(new_pwd) < 8:
        return False, "Child's new password must be at least 8 characters long."

    # Validate parent ownership
    mapping = fetch_one(
        """
        SELECT map_id FROM parent_child_map
        WHERE child_id = %s AND (parent_id = %s OR verified_parent_id = %s)
          AND (approved = TRUE OR approval_status = 'APPROVED')
        LIMIT 1
        """,
        (child_id, parent_id, parent_id),
    )
    if not mapping:
        return False, "Unauthorized: You can only reset passwords for your own approved children."

    new_hash = bcrypt.hashpw(new_pwd.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    execute("UPDATE users SET password_hash = %s WHERE user_id = %s AND role = 'CHILD'", (new_hash, child_id))
    return True, "Child's password updated successfully."
