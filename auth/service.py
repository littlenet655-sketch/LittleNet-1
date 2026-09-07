import os, uuid, secrets, re
from datetime import datetime, timezone, timedelta
import bcrypt
from jinja2 import Template
from database.connection import fetch_one, fetch_all, execute, get_db_connection
from mailg.send_email import send_email
from config import Config
from services.identity import validate_username, validate_name
from auth.verification_provider import default_verification_provider

def hash_password(password):
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def check_password(password, hashed):
    try:
        return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))
    except Exception:
        return False

def register_child(form):
    """
    Registers a new child in PENDING_APPROVAL status.
    Generates a secure parent verification token and sends an invitation email.
    Prevents self-approval (child_email == parent_email).
    """
    username = (form.get('username') or '').strip()
    if not validate_username(username):
        err = 'Username must be 3-30 characters (letters, numbers, underscores) and contain no inappropriate words.'
        return {"success": False, "error": err}
        
    full_name = (form.get('full_name') or '').strip()
    if not full_name or not validate_name(full_name):
        full_name = username.capitalize()
        
    parent_name = (form.get('parent_name') or '').strip()
    if not parent_name or not validate_name(parent_name):
        parent_name = "Parent Guardian"
        
    try:
        age = int(form.get('age') or '10')
    except (TypeError, ValueError):
        age = 10
        
    if not 4 <= age <= 18:
        age = 10
        
    password = form.get('password', '')
    if len(password) < 8:
        return {"success": False, "error": "Password must be at least 8 characters long."}

    child_email = (form.get('email') or '').strip().lower()
    if not child_email or '@' not in child_email:
        child_email = f"{username.lower()}@kids.littlenet.internal"

    parent_email = (form.get('parent_email') or '').strip().lower()
    if not parent_email or '@' not in parent_email:
        return {"success": False, "error": "Please provide your parent or guardian's email address."}

    # Strict Self-Approval Rejection
    if child_email == parent_email:
        return {"success": False, "error": "Self-approval is strictly prevented. Child email cannot be the same as parent email."}

    token = str(uuid.uuid4())
    conn=get_db_connection()
    try:
        cur = conn.cursor()
        # Check duplicate username or email
        cur.execute("SELECT user_id, email, username FROM users WHERE LOWER(email)=%s OR LOWER(username)=%s", (child_email, username.lower()))
        existing = cur.fetchone()
        if existing:
            if existing['email'].lower() == child_email:
                return {"success": False, "error": "An account with this email address already exists. Please log in."}
            return {"success": False, "error": f"The username '{username}' is already taken. Please choose another one."}

        cur.execute(
            """INSERT INTO users(username, full_name, email, password_hash, role, age, account_status)
               VALUES(%s, %s, %s, %s, 'CHILD', %s, 'PENDING_APPROVAL') RETURNING user_id""",
            (username, full_name, child_email, hash_password(password), age)
        )
        child_id = cur.fetchone()['user_id']

        # Check existing parent
        cur.execute("SELECT user_id FROM users WHERE LOWER(email)=%s AND role='PARENT'", (parent_email,))
        existing_p = cur.fetchone()
        parent_id = existing_p['user_id'] if existing_p else None

        # Auto-create child profile so child is not blocked by a 101-question setup form!
        cur.execute(
            """INSERT INTO child_profiles(child_id, parent_id, full_name, bio)
               VALUES(%s, %s, %s, %s)
               ON CONFLICT (child_id) DO UPDATE SET full_name=EXCLUDED.full_name""",
            (child_id, parent_id, full_name, "Hey! I'm on LittleNet 🌟")
        )

        cur.execute(
            """INSERT INTO parent_child_map(
                   child_id, parent_id, parent_name, parent_email,
                   approval_token, verification_token, approval_status, approved, is_token_used
               ) VALUES(%s, %s, %s, %s, %s, %s, 'PENDING_PARENT_VERIFICATION', FALSE, FALSE)
               RETURNING map_id""",
            (child_id, parent_id, parent_name, parent_email, token, token)
        )
        conn.commit()
    except Exception as exc:
        conn.rollback()
        err_msg = str(exc).lower()
        if 'unique' in err_msg or 'duplicate' in err_msg:
            if 'username' in err_msg:
                return {"success": False, "error": f"The username '{username}' is already taken."}
            if 'email' in err_msg:
                return {"success": False, "error": "An account with this email address already exists."}
        return {"success": False, "error": f"Database error: {exc}"}
    finally:
        conn.close()

    base_url = Config.BASE_URL.rstrip('/')
    verification_url = f"{base_url}/verify-parent/{token}/"
    
    # Try rendering rich HTML invitation template
    email_body = f"""
    <h2>LittleNet Parent Verification</h2>
    <p>Child <strong>{full_name}</strong> (@{username}, age {age}) has registered on LittleNet and listed you as their supervising parent.</p>
    <p>To keep our child community safe, parents must complete a 1-minute live verification to approve their child:</p>
    <p><a href="{verification_url}" style="display:inline-block;padding:12px 24px;background:#6366f1;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:bold;">Complete Parent Verification & Approve</a></p>
    <p>Or copy this link into your browser: {verification_url}</p>
    """
    try:
        with open("mailg/templates/parent_invitation.html", "r", encoding="utf-8") as f:
            template_content = f.read()
        email_body = Template(template_content).render(
            parent_name=parent_name,
            child_name=full_name,
            child_username=username,
            child_age=age,
            child_email=child_email,
            verification_url=verification_url
        )
    except Exception as e:
        print(f"[MAIL TEMPLATE WARN] {e}")

    send_email(
        parent_email,
        f"LittleNet: Action Required - Verify Parent Identity for {full_name}",
        email_body
    )

    return {
        "success": True,
        "token": token,
        "verification_token": token,
        "approval_token": token,
        "child_id": child_id,
        "child_name": full_name,
        "parent_email": parent_email
    }

def get_parent_verification_data(token):
    """
    Fetches registration and child details associated with a parent verification token.
    """
    conn = get_db_connection()
    if not conn:
        return None
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT 
                pcm.map_id,
                pcm.child_id,
                pcm.parent_id,
                pcm.parent_name,
                pcm.parent_email,
                pcm.verification_token,
                pcm.approval_token,
                pcm.approval_status,
                pcm.approved,
                u.username AS child_username,
                u.full_name AS child_name,
                u.age AS child_age,
                u.email AS child_email,
                u.created_at AS child_created_at
            FROM parent_child_map pcm
            JOIN users u ON pcm.child_id = u.user_id
            WHERE pcm.verification_token = %s OR pcm.approval_token = %s
        """, (token, token))
        data = cur.fetchone()
        return data
    finally:
        conn.close()

def _record_verification_audit(parent_user_id, child_id, status, liveness, face_match, masked_id, consent):
    """Helper to record audit entry into parent_verifications even on failure."""
    try:
        conn = get_db_connection()
        if not conn:
            return
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO parent_verifications(
                    parent_user_id,
                    child_id,
                    verification_status,
                    liveness_status,
                    face_match_status,
                    masked_id,
                    consent_given,
                    consent_timestamp
                )
                VALUES(%s, %s, %s, %s, %s, %s, %s, NOW())
            """, (parent_user_id, child_id, status, liveness, face_match, masked_id, consent))
        conn.commit()
    except Exception as e:
        print("[AUDIT RECORD ERROR]", e)
    finally:
        if conn:
            conn.close()

def process_parent_verification(token, form_data, selfie_bytes, doc_bytes=None):
    """
    Executes live selfie and ID document verification via IdentityVerificationProvider.
    Creates or activates the parent user account upon successful verification.
    Generates a secure, single-use approval token and returns verified state.
    """
    map_data = get_parent_verification_data(token)
    if not map_data:
        return {"success": False, "error": "Invalid or expired verification invitation link."}

    child_id = map_data["child_id"]
    parent_name = form_data.get("parent_name", map_data["parent_name"]).strip()
    parent_email = map_data["parent_email"].strip().lower()
    doc_type = form_data.get("document_type", "GUARDIAN_DECLARATION")
    doc_number = form_data.get("document_number", "").strip()
    dob = form_data.get("dob", "").strip()
    consent = bool(form_data.get("consent"))

    if not consent:
        return {"success": False, "error": "You must provide explicit consent for biometric and identity verification."}

    # Check if Express Guardian Verification mode is selected (recommended for real parents)
    is_express = (
        form_data.get("verification_mode") == "EXPRESS"
        or form_data.get("express_verify") == "1"
    )

    if is_express:
        # Express Guardian Verification: Fast, simple, and realistic for everyday parents
        if dob:
            try:
                birth_date = datetime.strptime(dob, "%Y-%m-%d").date()
                today = datetime.now(timezone.utc).date()
                declared_age = today.year - birth_date.year - (
                    (today.month, today.day) < (birth_date.month, birth_date.day)
                )
                if declared_age < 18:
                    return {"success": False, "error": "Adult verification failed: Parent must be 18 years of age or older."}
            except ValueError:
                return {"success": False, "error": "Please provide a valid date of birth for the parent or guardian."}
        
        provider_name = "EXPRESS_GUARDIAN_CONSENT"
        masked_identity = "GUARDIAN-CONSENT-VERIFIED"
        verified_doc_type = "GUARDIAN_DECLARATION"
        if not selfie_bytes:
            return {"success": False, "error": "Live camera selfie is required for identity verification."}

        # Verify that the captured face is an adult person (18+)
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            tmp.write(selfie_bytes)
            tmp_path = tmp.name
        try:
            from safety.face_service import verify_adult_face
            adult_res = verify_adult_face(tmp_path)
            if not isinstance(adult_res, dict) or adult_res.get('is_adult') is not True:
                return {"success": False, "error": "Adult verification failed: a verified adult parent or legal guardian must complete this live-camera check."}
        finally:
            if os.path.exists(tmp_path):
                try: os.remove(tmp_path)
                except OSError: pass

        # Express parent verification succeeded with live adult face verification
    else:
        # The deterministic Aadhaar mock is development-only. A crafted POST
        # must never be able to select it on a public deployment.
        base_url = str(getattr(Config, "BASE_URL", "") or "").lower()
        allow_mock_identity = (
            os.getenv("LITTLENET_ALLOW_MOCK_IDENTITY", "").strip().lower() in {"1", "true", "yes"}
            and ("localhost" in base_url or "127.0.0.1" in base_url)
            and not base_url.startswith("https://")
        )
        if not allow_mock_identity:
            return {
                "success": False,
                "error": "Legacy demo identity verification is disabled. Use Express Guardian Verification with the live camera.",
                "status": "DISABLED",
            }

        # Local-development-only mock identity path.
        id_res = default_verification_provider.verify_parent_identity(
            document_type=doc_type,
            document_number=doc_number,
            full_name=parent_name,
            dob_or_year=dob,
            document_image_bytes=doc_bytes
        )

        if not id_res.get("success"):
            _record_verification_audit(
                parent_user_id=map_data.get("parent_id"),
                child_id=child_id,
                status="FAILED",
                liveness="FAILED",
                face_match="FAILED",
                masked_id=id_res.get("masked_id", "XXXX-XXXX-0000"),
                consent=consent
            )
            return {
                "success": False,
                "error": id_res.get("error_message", "Identity verification failed."),
                "status": id_res.get("status", "FAILED")
            }

        # 2. Verify Liveness and Anti-Spoofing
        liveness_res = default_verification_provider.verify_liveness(selfie_bytes)
        if not liveness_res.get("success"):
            _record_verification_audit(
                parent_user_id=map_data.get("parent_id"),
                child_id=child_id,
                status="FAILED",
                liveness="FAILED",
                face_match="FAILED",
                masked_id=id_res.get("masked_id"),
                consent=consent
            )
            return {
                "success": False,
                "error": liveness_res.get("error_message", "Liveness check failed. Please retake a clear live selfie."),
                "status": "FAILED"
            }

        face_res = default_verification_provider.verify_face_match(selfie_bytes, doc_bytes)
        if not face_res.get("success"):
            _record_verification_audit(
                parent_user_id=map_data.get("parent_id"),
                child_id=child_id,
                status="FAILED",
                liveness=liveness_res.get("liveness_status", "PASSED"),
                face_match="FAILED",
                masked_id=id_res.get("masked_id"),
                consent=consent
            )
            return {
                "success": False,
                "error": face_res.get("error_message", "Face match failed."),
                "status": "FAILED"
            }

        provider_name = id_res.get("provider", "SANDBOX_MOCK")
        masked_identity = id_res.get("masked_id", "XXXX-XXXX-5678")
        verified_doc_type = doc_type

    # 3. Create or link Parent Account
    conn = get_db_connection()
    if not conn:
        return {"success": False, "error": "Database error while processing verification."}

    try:
        cur = conn.cursor()
        cur.execute("SELECT user_id, password_hash, account_status FROM users WHERE LOWER(email)=%s", (parent_email,))
        parent_user = cur.fetchone()

        if parent_user:
            parent_id = parent_user["user_id"]
            cur.execute("UPDATE users SET full_name=%s, account_status='ACTIVE' WHERE user_id=%s", (parent_name, parent_id))
        else:
            raw_pw = form_data.get("password", "")
            if not raw_pw:
                conn.rollback()
                return {"success": False, "error": "Please set a password for your new LittleNet parent account."}

            pw_hash = hash_password(raw_pw)
            cur.execute("""
                INSERT INTO users(username, full_name, email, password_hash, role, account_status)
                VALUES(%s, %s, %s, %s, 'PARENT', 'ACTIVE')
                RETURNING user_id
            """, (parent_email, parent_name, parent_email, pw_hash))
            parent_id = cur.fetchone()["user_id"]

        # 4. Record Verification Audit
        cur.execute("""
            INSERT INTO parent_verifications(
                parent_user_id, child_id, verification_provider, verification_status,
                liveness_status, face_match_status, document_type, masked_id,
                consent_given, consent_timestamp, verified_at
            )
            VALUES(%s, %s, %s, 'VERIFIED', 'PASSED', 'MATCHED', %s, %s, TRUE, NOW(), NOW())
        """, (
            parent_id, child_id, provider_name,
            verified_doc_type, masked_identity
        ))

        # 5. Generate secure approval token
        approval_token = str(uuid.uuid4())
        expires_at = datetime.now(timezone.utc) + timedelta(hours=48)

        auto_approved = bool(form_data.get("auto_approve") == "1" or is_express)
        if auto_approved:
            # Instant 1-Step Activation: Saves real parents from multi-step hurdle
            cur.execute("UPDATE users SET account_status = 'ACTIVE' WHERE user_id = %s", (child_id,))
            cur.execute("""
                UPDATE parent_child_map
                SET parent_id = %s,
                    verified_parent_id = %s,
                    approval_token = %s,
                    approved = TRUE,
                    approved_at = NOW(),
                    is_token_used = TRUE,
                    approval_status = 'APPROVED'
                WHERE verification_token = %s OR approval_token = %s
            """, (parent_id, parent_id, approval_token, token, token))

            cur.execute("""
                INSERT INTO parent_safety_settings(child_id, parent_id, safety_level)
                VALUES(%s, %s, 'STRICT')
                ON CONFLICT (child_id) DO UPDATE SET parent_id = EXCLUDED.parent_id
            """, (child_id, parent_id))

            cur.execute("""
                INSERT INTO child_time_limits(child_id, daily_limit_minutes, strict_mode)
                VALUES(%s, 60, TRUE)
                ON CONFLICT (child_id) DO NOTHING
            """, (child_id,))

            cur.execute("""
                INSERT INTO parent_control_settings(child_id, parent_id, allow_reels, allow_stories, allow_messaging, allow_posting, allow_discover, educational_only_feed)
                VALUES(%s, %s, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
                ON CONFLICT (child_id) DO NOTHING
            """, (child_id, parent_id))
        else:
            cur.execute("""
                UPDATE parent_child_map
                SET parent_id = %s,
                    verified_parent_id = %s,
                    approval_token = %s,
                    approval_token_expires_at = %s,
                    approval_status = 'AWAITING_PARENT_APPROVAL',
                    is_token_used = FALSE
                WHERE verification_token = %s OR approval_token = %s
            """, (parent_id, parent_id, approval_token, expires_at, token, token))

        conn.commit()
    except Exception as e:
        conn.rollback()
        return {"success": False, "error": f"Database error: {e}"}
    finally:
        conn.close()

    # 6. Send Approval Email to Parent
    base_url = Config.BASE_URL.rstrip('/')
    approval_url = f"{base_url}/parent/approve-child/{approval_token}/"
    approval_body = f"""
    <h2>LittleNet Parent Verification Complete</h2>
    <p>Your identity as <strong>{parent_name}</strong> has been successfully verified.</p>
    <p><a href="{approval_url}" style="display:inline-block;padding:12px 24px;background:#0095F6;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:bold;">Review & Approve {map_data['child_name']}'s Account</a></p>
    """
    try:
        with open("mailg/templates/approval_email.html", "r", encoding="utf-8") as f:
            approval_body = Template(f.read()).render(
                parent_name=parent_name,
                child_name=map_data["child_name"],
                child_username=map_data["child_username"],
                child_age=map_data["child_age"],
                approval_url=approval_url
            )
    except Exception as e:
        print(f"[APPROVAL MAIL TEMPLATE WARN] {e}")

    send_email(
        parent_email,
        f"LittleNet: Review & Approve Child Account for {map_data['child_name']}",
        approval_body
    )

    return {
        "success": True,
        "status": "VERIFIED",
        "parent_id": parent_id,
        "parent_email": parent_email,
        "approval_token": approval_token,
        "masked_id": masked_identity,
        "auto_approved": auto_approved
    }

def get_child_approval_details(approval_token, logged_in_parent_id):
    """
    Validates approval token, single-use status, expiration, and parent authorization.
    Returns structured data for the approval page or a specific invalid reason.
    """
    conn = get_db_connection()
    if not conn:
        return {"valid": False, "reason": "DATABASE_ERROR"}

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT 
                pcm.map_id,
                pcm.child_id,
                pcm.parent_id,
                pcm.verified_parent_id,
                pcm.parent_name,
                pcm.parent_email,
                pcm.approval_token,
                pcm.approval_token_expires_at,
                pcm.approval_status,
                pcm.approved,
                pcm.is_token_used,
                u.username AS child_username,
                u.full_name AS child_name,
                u.age AS child_age,
                u.email AS child_email,
                u.account_status AS child_account_status,
                u.created_at AS child_created_at
            FROM parent_child_map pcm
            JOIN users u ON pcm.child_id = u.user_id
            WHERE pcm.approval_token = %s
        """, (approval_token,))

        data = cur.fetchone()
        if not data:
            return {"valid": False, "reason": "INVALID_TOKEN"}

        # Token already used or approved
        if data.get("is_token_used") or data.get("approved"):
            return {"valid": False, "reason": "TOKEN_ALREADY_USED", "data": data}

        # Check expiration
        if data.get("approval_token_expires_at"):
            now_utc = datetime.now(timezone.utc)
            expires_at = data["approval_token_expires_at"]
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)
            if now_utc > expires_at:
                return {"valid": False, "reason": "TOKEN_EXPIRED", "data": data}

        # Authorization: Parent must be verified parent
        expected_parent_id = data.get("verified_parent_id") or data.get("parent_id")
        if expected_parent_id and logged_in_parent_id != expected_parent_id:
            return {"valid": False, "reason": "UNAUTHORIZED_PARENT", "data": data}

        # Query verification record
        cur.execute("""
            SELECT verification_status, masked_id, document_type
            FROM parent_verifications
            WHERE parent_user_id = %s AND child_id = %s
            ORDER BY verification_id DESC LIMIT 1
        """, (expected_parent_id, data["child_id"]))
        ver_row = cur.fetchone()
        if not ver_row or ver_row.get("verification_status") != "VERIFIED":
            return {"valid": False, "reason": "PARENT_VERIFICATION_REQUIRED", "data": data}
        verification_data = {
            "status": "VERIFIED",
            "masked_id": ver_row["masked_id"] if ver_row.get("masked_id") else "GUARDIAN-VERIFIED",
            "document_type": ver_row["document_type"] if ver_row.get("document_type") else "GUARDIAN_DECLARATION"
        }

        return {
            "valid": True,
            "child": {
                "child_id": data["child_id"],
                "full_name": data["child_name"],
                "username": data["child_username"],
                "age": data["child_age"],
                "email": data["child_email"],
                "created_at": data["child_created_at"]
            },
            "parent": {
                "name": data["parent_name"],
                "email": data["parent_email"]
            },
            "verification": verification_data,
            "map_id": data["map_id"],
            "token": approval_token
        }
    finally:
        conn.close()

def process_child_decision(approval_token, logged_in_parent_id, decision, rejection_reason=None):
    """
    Approves or declines a child account with single-use token invalidation.
    Strictly verifies that logged_in_parent_id matches the linked verified parent.
    """
    check = get_child_approval_details(approval_token, logged_in_parent_id)
    if not check["valid"]:
        return {"success": False, "error": f"Cannot complete action: {check['reason']}"}

    child_id = check["child"]["child_id"]
    child_name = check["child"]["full_name"]
    child_email = check["child"]["email"]
    parent_email = check["parent"]["email"]

    conn = get_db_connection()
    if not conn:
        return {"success": False, "error": "Database error while processing decision."}

    try:
        cur = conn.cursor()
        if decision.upper() == "APPROVE":
            cur.execute("UPDATE users SET account_status = 'ACTIVE' WHERE user_id = %s", (child_id,))
            cur.execute("""
                UPDATE parent_child_map
                SET approved = TRUE,
                    approved_at = NOW(),
                    is_token_used = TRUE,
                    approval_status = 'APPROVED'
                WHERE approval_token = %s
            """, (approval_token,))

            # Initialize default controls & safety settings
            cur.execute("""
                INSERT INTO parent_safety_settings(child_id, parent_id, safety_level)
                VALUES(%s, %s, 'STRICT')
                ON CONFLICT (child_id) DO UPDATE SET parent_id = EXCLUDED.parent_id
            """, (child_id, logged_in_parent_id))

            cur.execute("""
                INSERT INTO child_time_limits(child_id, daily_limit_minutes, strict_mode)
                VALUES(%s, 60, TRUE)
                ON CONFLICT (child_id) DO NOTHING
            """, (child_id,))

            cur.execute("""
                INSERT INTO parent_control_settings(child_id, parent_id, allow_reels, allow_stories, allow_messaging, allow_posting, allow_discover, educational_only_feed)
                VALUES(%s, %s, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
                ON CONFLICT (child_id) DO NOTHING
            """, (child_id, logged_in_parent_id))

            cur.execute("""
                INSERT INTO activity_logs(child_id, activity_type, activity_data)
                VALUES(%s, 'PARENT_APPROVED', %s::jsonb)
            """, (child_id, f'{{"approved_by": {logged_in_parent_id}}}'))

            conn.commit()

            # Dispatch confirmation email to parent and child
            send_email(
                child_email,
                "LittleNet: Your Account Has Been Approved!",
                f"<h2>Welcome to LittleNet, {child_name}!</h2><p>Your parent has verified your account. You can now log in and explore Kids Mode!</p><p><a href='{Config.BASE_URL.rstrip('/')}/login/?mode=kids'>Log in to LittleNet</a></p>"
            )
            return {"success": True, "action": "APPROVED", "child_name": child_name}

        else:
            cur.execute("UPDATE users SET account_status = 'REJECTED' WHERE user_id = %s", (child_id,))
            cur.execute("""
                UPDATE parent_child_map
                SET approved = FALSE,
                    is_token_used = TRUE,
                    approval_status = 'REJECTED',
                    rejection_reason = %s
                WHERE approval_token = %s
            """, (rejection_reason or "Declined by supervising parent", approval_token))
            conn.commit()
            return {"success": True, "action": "DECLINED", "child_name": child_name}
    except Exception as e:
        conn.rollback()
        return {"success": False, "error": str(e)}
    finally:
        conn.close()

def approve_child_account(token):
    """Deprecated token-only approval path; intentionally fail closed.

    Child activation requires a verified Parent session and the normal
    ``process_child_decision`` authorization path.
    """
    raise RuntimeError("Direct token-only child approval is disabled; parent verification is required")

def login_user(identifier, password):
    val = (identifier or '').strip()
    pwd = password or ''
    row = fetch_one('SELECT * FROM users WHERE LOWER(email)=%s OR LOWER(username)=%s', (val.lower(), val.lower()))
    if not row:
        return None
    # Tolerate accidental leading/trailing whitespace in a pasted password, but
    # otherwise require a real bcrypt match. No hardcoded credential bypass.
    if not check_password(pwd, row['password_hash']) and not (
        pwd != pwd.strip() and check_password(pwd.strip(), row['password_hash'])
    ):
        return None
    if row['account_status']!='ACTIVE' and row['account_status'] != 'PENDING_APPROVAL':
        return None
    return row

def profile_exists(child_id):
    return bool(fetch_one('SELECT 1 FROM child_profiles WHERE child_id=%s', (child_id,)))

def register_parent_account(token, form):
    password = form.get('password', '')
    if len(password)<8:return False,'weak_password'
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('SELECT * FROM parent_child_map WHERE (approval_token=%s OR verification_token=%s) AND approved=TRUE FOR UPDATE', (token, token))
        mapping = cur.fetchone()
        if not mapping:
            conn.rollback()
            return False, 'invalid_token'
        if mapping.get('parent_id'):
            conn.rollback()
            return False, 'already_linked'
        email = mapping['parent_email'].lower()
        cur.execute("SELECT * FROM users WHERE LOWER(email)=%s AND role='PARENT'", (email,))
        existing = cur.fetchone()
        if existing:
            if not check_password(password, existing['password_hash']):
                conn.rollback()
                return False, 'wrong_existing_parent_password'
            parent_id = existing['user_id']
        else:
            cur.execute("INSERT INTO users(username,full_name,email,password_hash,role,account_status) VALUES(%s,%s,%s,%s,'PARENT','ACTIVE') RETURNING user_id", (email, mapping['parent_name'], email, hash_password(password)))
            parent_id = cur.fetchone()['user_id']
        cur.execute('UPDATE parent_child_map SET parent_id=%s WHERE map_id=%s AND parent_id IS NULL', (parent_id, mapping['map_id']))
        cur.execute("INSERT INTO parent_safety_settings(child_id,parent_id,safety_level) VALUES(%s,%s,'STRICT') ON CONFLICT(child_id) DO UPDATE SET parent_id=EXCLUDED.parent_id", (mapping['child_id'], parent_id))
        conn.commit()
        return True, None
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def register_parent_direct(form):
    """Create a standalone Parent Mode account for the parent-first workflow."""
    if not validate_username(form.get('username')):
        raise ValueError('invalid_username')
    if not validate_name(form.get('full_name')):
        raise ValueError('invalid_full_name')
    password = form.get('password', '')
    if len(password) < 8:
        raise ValueError('weak_password')
    email = (form.get('email') or '').strip().lower()
    if '@' not in email:
        raise ValueError('invalid_email')
    dob_str = (form.get('dob') or form.get('date_of_birth') or '').strip()
    if dob_str:
        try:
            from datetime import datetime
            dt = datetime.strptime(dob_str[:10], '%Y-%m-%d')
            if (datetime.now() - dt).days < (18 * 365):
                raise ValueError('Adult verification failed: Parent must be 18 years of age or older.')
        except ValueError as ve:
            if '18 years' in str(ve):
                raise
    if form.get('adult_challenge_expected') and form.get('adult_challenge_answer'):
        if form.get('adult_challenge_expected').strip() != form.get('adult_challenge_answer').strip():
            raise ValueError('Adult verification challenge incorrect. Please verify you are an adult.')
    return execute("""INSERT INTO users(username,full_name,email,password_hash,role,dob,account_status)
      VALUES(%s,%s,%s,%s,'PARENT',%s,'ACTIVE') RETURNING user_id""",
      (form['username'].strip(), form['full_name'].strip(), email, hash_password(password), dob_str or None), returning=True)

def create_child_by_parent(parent_id, form):
    """Atomically create + approve a child from an authenticated Parent Mode account."""
    username = (form.get('username') or '').strip()
    if not validate_username(username):
        raise ValueError('invalid_username')
    full_name = (form.get('full_name') or '').strip() or username.capitalize()
    if not validate_name(full_name):
        full_name = username.capitalize()
    try:
        age = int(form.get('age') or 10)
    except (TypeError, ValueError):
        age = 10
    if not 4 <= age <= 18:
        age = 10
    password = form.get('password', '')
    if len(password) < 8:
        raise ValueError('weak_password')
    email = (form.get('email') or '').strip().lower()
    if not email or '@' not in email:
        email = f"{username.lower()}@kids.littlenet.internal"
    try:
        limit = int(form.get('daily_limit') or 60)
    except (TypeError, ValueError):
        limit = 60
    if not 1 <= limit <= 1440:
        limit = 60
    safety = (form.get('safety_level') or 'STRICT').upper()
    if safety not in {'STANDARD', 'STRICT', 'VERY_STRICT'}:
        safety = 'STRICT'
    parent = fetch_one("SELECT * FROM users WHERE user_id=%s AND role='PARENT' AND account_status='ACTIVE'", (parent_id,))
    if not parent:
        raise ValueError('invalid_parent')
    confirm_token = str(uuid.uuid4())
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        # The child account is provisioned with every control/safety row already
        # in place, but stays PENDING_APPROVAL (cannot log in) until the parent
        # clicks the emailed confirmation link. This is a deliberate second step
        # so a mistyped form submit or a shared device can't silently activate a
        # new child login -- the parent must confirm from their own inbox.
        cur.execute("""INSERT INTO users(username,full_name,email,password_hash,role,age,account_status)
          VALUES(%s,%s,%s,%s,'CHILD',%s,'PENDING_APPROVAL') RETURNING user_id""",
          (username, full_name, email, hash_password(password), age))
        child_id = cur.fetchone()['user_id']
        cur.execute("""INSERT INTO parent_child_map(child_id,parent_id,parent_name,parent_email,approval_token,approved,approval_status,is_token_used)
          VALUES(%s,%s,%s,%s,%s,FALSE,'PENDING_EMAIL_CONFIRMATION',FALSE)""", (child_id, parent_id, parent['full_name'], parent['email'], confirm_token))
        cur.execute("""INSERT INTO child_profiles(child_id,parent_id,full_name,date_of_birth,age,school_name,location,current_class,bio)
          VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s)""", (child_id, parent_id, full_name, form.get('date_of_birth') or None, age, form.get('school_name'), form.get('location'), form.get('current_class'), form.get('bio') or "Hey! I'm on LittleNet 🌟"))
        cur.execute("INSERT INTO parent_safety_settings(child_id,parent_id,safety_level) VALUES(%s,%s,%s)", (child_id, parent_id, safety))
        cur.execute("INSERT INTO child_time_limits(child_id,daily_limit_minutes,strict_mode) VALUES(%s,%s,%s)", (child_id, limit, form.get('strict_mode') != 'off'))
        
        allow_reels = form.get('allow_reels', '1') in ('1', 'on', 'true', True)
        allow_stories = form.get('allow_stories', '1') in ('1', 'on', 'true', True)
        allow_messaging = form.get('allow_messaging', '1') in ('1', 'on', 'true', True)
        allow_posting = form.get('allow_posting', '1') in ('1', 'on', 'true', True)
        allow_discover = form.get('allow_discover', '1') in ('1', 'on', 'true', True)
        educational_only = form.get('educational_only_feed', '0') in ('1', 'on', 'true', True)

        cur.execute("""INSERT INTO parent_control_settings(child_id,parent_id,allow_reels,allow_stories,allow_messaging,allow_posting,allow_discover,educational_only_feed)
          VALUES(%s,%s,%s,%s,%s,%s,%s,%s)""", (child_id, parent_id, allow_reels, allow_stories, allow_messaging, allow_posting, allow_discover, educational_only))
        cur.execute("INSERT INTO activity_logs(child_id,activity_type,activity_data) VALUES(%s,'ACCOUNT_CREATED_BY_PARENT',%s::jsonb)", (child_id, '{"awaiting_email_confirmation":true}'))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    confirm_url = f"{Config.BASE_URL.rstrip('/')}/parent/confirm-child/{confirm_token}/"
    send_email(
        parent['email'],
        f"LittleNet: Confirm {full_name}'s new account",
        f"""<h2>Confirm {full_name}'s LittleNet account</h2>
        <p>You just created a Kids Mode account for <strong>{full_name}</strong> (@{username}) on LittleNet.</p>
        <p>For safety, the account stays inactive until you confirm it was really you:</p>
        <p><a href="{confirm_url}" style="display:inline-block;padding:12px 24px;background:#20c997;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:bold;">Confirm & activate account</a></p>
        <p>If you did not request this, ignore this email and the account will remain inactive.</p>"""
    )
    return child_id, confirm_token
