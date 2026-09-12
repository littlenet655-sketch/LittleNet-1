from __future__ import annotations

import base64
import os
import random
import secrets
import tempfile
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from functools import wraps
from urllib.parse import quote

from flask import g, jsonify, redirect, request, send_from_directory
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from werkzeug.datastructures import MultiDict

from auth.child_provisioning import create_child_for_verified_parent
from auth.parent_email_otp import (
    begin_parent_registration,
    resend_parent_email_otp,
    verify_parent_email_otp,
)
from auth.password_reset import (
    parent_reset_child_password,
    request_password_reset,
    verify_and_reset_password,
)
from auth.service import login_user
from child.service import (
    can_discover_child,
    counts,
    create_child_profile,
    discoverable_children,
    follow_child,
    get_child_profile,
    get_random_children,
    is_follow_pending,
    is_following,
    profile_exists,
    replace_profile_tags,
    unfollow_child,
)
from childMessage.service import conversation, messages
from config import Config
from database.connection import execute, fetch_all, fetch_one, get_db_connection
from extensions import csrf, limiter
from parent.service import children, owns, pending_follows
from quiz.service import (
    age_group,
    complete_required_feed_quiz,
    feed_quiz_state,
    learning_challenges,
    learning_points,
    needs_onboarding_quiz,
    quizzes,
    record_feed_answer,
    record_feed_view,
    required_feed_quiz,
)
from safety.face_service import enroll, verify, verify_adult_face
from safety.moderation_service import evaluate, record, safety_level
from safety.pii_service import scan_pii
from safety.policy import Decision, decide
from services.behavior import behavior_summary
from services.controls import (
    SAFE_CATEGORIES,
    controls_for_child,
    effective_categories,
    feature_allowed,
    quiet_hours_state,
    save_controls,
)
from services.curated_feed import (
    _child_real_age,
    authorize_curated_media,
    get_feed_page,
    record_feed_impression,
    search_curated_content,
)
from services.social import (
    active_stories,
    can_interact,
    discoverable_posts,
    notify,
    parent_notify,
    post_visible_to,
    visible_posts,
    visible_profile_posts,
)
from services.usage import close_session, heartbeat, lock_state, minutes_today, online_state, start_session


_AUTH_SALT = "littlenet-native-auth-v1"
_PENDING_PARENT_SALT = "littlenet-native-parent-pending-v1"
_TOKEN_TTL = int(os.getenv("LITTLENET_MOBILE_TOKEN_TTL_SECONDS", "86400"))
_PENDING_TTL = 30 * 60


def _serializer(salt: str) -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(Config.SECRET_KEY, salt=salt)


def _clean(value):
    if isinstance(value, dict):
        blocked = {"password_hash", "approval_token", "verification_token"}
        return {k: _clean(v) for k, v in value.items() if k not in blocked}
    if isinstance(value, (list, tuple)):
        return [_clean(v) for v in value]
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, uuid.UUID):
        return str(value)
    return value


def _issue_token(user: dict, usage_session_key=None) -> str:
    claims = {
        "uid": int(user["user_id"]),
        "role": user["role"],
        "name": user.get("full_name") or user.get("username") or "LittleNet User",
    }
    if usage_session_key:
        claims["usage_session_key"] = str(usage_session_key)
    return _serializer(_AUTH_SALT).dumps(claims)


def _issue_pending_parent(user_id: int, email: str) -> str:
    return _serializer(_PENDING_PARENT_SALT).dumps({"uid": int(user_id), "email": email})


def _load_pending_parent(token: str):
    try:
        return _serializer(_PENDING_PARENT_SALT).loads(token, max_age=_PENDING_TTL)
    except (BadSignature, SignatureExpired):
        return None


def _bearer_token() -> str:
    header = request.headers.get("Authorization", "")
    if not header.lower().startswith("bearer "):
        return ""
    return header.split(" ", 1)[1].strip()


def _load_claims():
    token = _bearer_token()
    if not token:
        return None
    try:
        return _serializer(_AUTH_SALT).loads(token, max_age=_TOKEN_TTL)
    except (BadSignature, SignatureExpired):
        return None


def _require_mobile(*roles):
    allowed = {r.upper() for r in roles}

    def decorator(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            claims = _load_claims()
            if not claims:
                return jsonify(error="mobile_auth_required"), 401
            user = fetch_one(
                "SELECT user_id,username,full_name,email,role,age,account_status FROM users WHERE user_id=%s",
                (int(claims.get("uid") or 0),),
            )
            if not user or user.get("account_status") != "ACTIVE":
                return jsonify(error="account_inactive"), 401
            if allowed and str(user.get("role") or "").upper() not in allowed:
                return jsonify(error="role_forbidden"), 403
            if str(user.get("role")) != str(claims.get("role")):
                return jsonify(error="token_role_mismatch"), 401
            g.mobile_claims = claims
            g.mobile_user = user
            return fn(*args, **kwargs)

        return wrapped

    return decorator


def _child_gate(feature: str | None = None):
    uid = int(g.mobile_user["user_id"])
    face = fetch_one("SELECT 1 FROM face_profiles WHERE child_id=%s LIMIT 1", (uid,))
    if not face:
        return jsonify(error="face_enrollment_required", gate="face"), 428
    if needs_onboarding_quiz(uid):
        return jsonify(error="onboarding_quiz_required", gate="quiz"), 428
    if feature and not feature_allowed(uid, feature):
        return jsonify(error="disabled_by_parent", feature=feature), 403
    quiet = quiet_hours_state(uid)
    if quiet.get("active"):
        return jsonify(error="quiet_hours", gate="quiet_hours", quiet=_clean(quiet)), 423
    locked, remaining = lock_state(uid)
    if locked:
        return jsonify(error="screen_time_limit", gate="screen_time", remaining=remaining), 423
    if feed_quiz_state(uid).get("required"):
        return jsonify(error="quiz_required", gate="quiz"), 428
    key = (g.mobile_claims or {}).get("usage_session_key")
    if key:
        try:
            heartbeat(key)
        except Exception:
            pass
    return None


def _asset_url(reference, viewer_id=None, viewer_role=None):
    if not reference:
        return None
    from services.media_delivery import resolve_media_delivery

    v_id = viewer_id
    v_role = viewer_role
    if v_id is None and hasattr(g, "mobile_user") and g.mobile_user:
        v_id = g.mobile_user.get("user_id")
        v_role = g.mobile_user.get("role")
    res = resolve_media_delivery(reference, viewer_id=v_id, viewer_role=v_role)
    return res.get("url")


def _profile_json(row):
    if not row:
        return None
    out = dict(row)
    out["avatar_url"] = _asset_url(out.get("profile_picture"))
    out.pop("profile_picture", None)
    return _clean(out)


def _post_json(row, viewer_id=None):
    if not row:
        return None
    out = dict(row)
    v_id = viewer_id
    v_role = None
    if v_id is None and hasattr(g, "mobile_user") and g.mobile_user:
        v_id = g.mobile_user.get("user_id")
        v_role = g.mobile_user.get("role")
    elif v_id and hasattr(g, "mobile_user") and g.mobile_user:
        v_role = g.mobile_user.get("role")

    from services.media_delivery import resolve_media_delivery

    media_res = resolve_media_delivery(out.get("media_path"), viewer_id=v_id, viewer_role=v_role)
    avatar_res = resolve_media_delivery(out.get("profile_picture"), viewer_id=v_id, viewer_role=v_role)
    poster_res = resolve_media_delivery(out.get("poster_path"), viewer_id=v_id, viewer_role=v_role)

    out["media_url"] = media_res.get("url")
    out["avatar_url"] = avatar_res.get("url")
    out["poster_url"] = poster_res.get("url")
    if media_res.get("expires_at"):
        out["playback_expires_at"] = media_res["expires_at"]
    out.pop("media_path", None)
    out.pop("poster_path", None)
    out.pop("profile_picture", None)
    out.pop("story_music_path", None)
    if viewer_id and out.get("post_id"):
        pid = int(out["post_id"])
        out["viewer_liked"] = bool(fetch_one("SELECT 1 FROM likes WHERE post_id=%s AND child_id=%s", (pid, viewer_id)))
        out["viewer_saved"] = bool(fetch_one("SELECT 1 FROM saved_posts WHERE post_id=%s AND child_id=%s", (pid, viewer_id)))
    if out.get("post_id"):
        from services.tag_service import get_post_tags

        out["tags"] = get_post_tags(int(out["post_id"]))

    if out.get("is_story") and (out.get("story_music_id") or out.get("story_music_url")):
        out["story_music"] = {
            "music_id": out.get("story_music_id"),
            "title": out.get("story_music_title") or "Curated Music",
            "artist": out.get("story_music_artist") or "LittleNet",
            "audio_url": out.get("story_music_url"),
            "start_seconds": out.get("story_music_start") or 0,
            "duration_seconds": out.get("story_music_duration") or 30,
        }

    return _clean(out)


def _save_request_image(prefix: str):
    upload = request.files.get("photo") or request.files.get("media")
    if upload and upload.filename:
        suffix = os.path.splitext(upload.filename)[1].lower() or ".jpg"
        fd, path = tempfile.mkstemp(prefix=prefix, suffix=suffix)
        os.close(fd)
        upload.save(path)
        if os.path.getsize(path) > Config.MAX_CONTENT_LENGTH:
            try:
                os.unlink(path)
            except OSError:
                pass
            return None
        return path
    data = request.get_json(silent=True) or {}
    raw = str(data.get("photo_b64") or data.get("selfie_data") or "").strip()
    if not raw:
        return None
    if "base64," in raw:
        raw = raw.split("base64,", 1)[1]
    try:
        blob = base64.b64decode(raw, validate=True)
    except Exception:
        return None
    if len(blob) < 1000 or len(blob) > 8 * 1024 * 1024:
        return None
    fd, path = tempfile.mkstemp(prefix=prefix, suffix=".jpg")
    os.close(fd)
    with open(path, "wb") as handle:
        handle.write(blob)
    return path


def _mobile_user_payload(user):
    profile = None
    quiz_required = False
    posts_seen = 0
    quiz_interval = 4
    if user.get("role") == "CHILD":
        uid = int(user["user_id"])
        profile = _profile_json(get_child_profile(uid))
        q_state = feed_quiz_state(uid)
        quiz_required = bool(q_state.get("required") or needs_onboarding_quiz(uid))
        posts_seen = int(q_state.get("posts_seen", 0))
        quiz_interval = int(q_state.get("interval", 4))
    return {
        "user_id": int(user["user_id"]),
        "username": user.get("username"),
        "full_name": user.get("full_name"),
        "email": user.get("email"),
        "role": user.get("role"),
        "age": user.get("age"),
        "profile": profile,
        "quiz_required": quiz_required,
        "posts_seen": posts_seen,
        "quiz_interval": quiz_interval,
    }


def _mobile_login_response(user, method="PASSWORD"):
    usage_key = None
    if user["role"] == "CHILD":
        started = start_session(user["user_id"])
        usage_key = started.get("session_key") if started else None
    token = _issue_token(user, usage_key)
    response = {
        "ok": True,
        "token": token,
        "auth_method": method,
        "user": _mobile_user_payload(user),
    }
    face_prof = fetch_one("SELECT biometric_key FROM face_profiles WHERE child_id=%s", (user["user_id"],))
    if face_prof and face_prof.get("biometric_key"):
        response["biometric_key"] = face_prof["biometric_key"]
    if user["role"] == "CHILD":
        uid = int(user["user_id"])
        response["onboarding"] = {
            "face_required": not bool(fetch_one("SELECT 1 FROM face_profiles WHERE child_id=%s", (uid,))),
            "quiz_required": bool(feed_quiz_state(uid).get("required") or needs_onboarding_quiz(uid)),
        }
    return jsonify(_clean(response))


def _media_allowed(uid: int, role: str, ref: str) -> bool:
    p = fetch_one("SELECT post_id,child_id,moderation_status,is_safe FROM posts WHERE media_path=%s OR story_music_path=%s", (ref, ref))
    if p:
        if role == "ADMIN":
            return True
        if role == "PARENT":
            return owns(uid, p["child_id"])
        return bool(post_visible_to(uid, p["post_id"]))
    m = fetch_one("SELECT sender_child_id,receiver_child_id,moderation_status FROM child_messages WHERE media_path=%s", (ref,))
    if m:
        if role == "ADMIN":
            return True
        if role == "PARENT":
            return owns(uid, m["sender_child_id"]) and m.get("moderation_status") == "REVIEW"
        return uid in {m["sender_child_id"], m["receiver_child_id"]} and can_interact(m["sender_child_id"], m["receiver_child_id"])
    f = fetch_one("SELECT child_id FROM child_profiles WHERE profile_picture=%s", (ref,))
    if f:
        if role == "ADMIN":
            return True
        if role == "PARENT":
            return owns(uid, f["child_id"])
        return can_discover_child(uid, f["child_id"])
    cur = fetch_one(
        """SELECT cc.content_id, cc.min_age, cc.max_age, cc.publish_status, cat.display_name, cat.active,
                  cma.moderation_status, cma.is_safe
           FROM curated_media_assets cma
           JOIN curated_content cc ON cc.asset_id = cma.asset_id
           JOIN content_categories cat ON cat.category_id = cc.category_id
           WHERE cma.delivery_object_key = %s OR cma.original_object_key = %s OR cma.poster_object_key = %s OR cma.thumbnail_object_key = %s""",
        (ref, ref, ref, ref),
    )
    if cur:
        if role in {"ADMIN", "PARENT"}:
            return True
        if role == "CHILD":
            if cur.get("publish_status") != "PUBLISHED" or cur.get("moderation_status") != "ALLOWED" or not cur.get("is_safe"):
                return False
            if not cur.get("active") or cur.get("display_name") not in effective_categories(uid):
                return False
            child_age = _child_real_age(uid)
            return bool(cur["min_age"] <= child_age <= cur["max_age"])
    return ref == "uploads/profile_pictures/download.webp" and role in {"CHILD", "PARENT", "ADMIN"}


def _merge_signals(*signals):
    out = {
        "adult_score": 0.0,
        "violence_score": 0.0,
        "weapon_score": 0.0,
        "toxicity_score": 0.0,
        "general_score": 0.0,
        "partial_safety_failure": False,
        "total_safety_failure": False,
        "sources": [],
    }
    valid = [s for s in signals if s]
    if not valid:
        out["total_safety_failure"] = True
        return out
    for sig in valid:
        for key in ("adult_score", "violence_score", "weapon_score", "toxicity_score", "general_score"):
            out[key] = max(float(out.get(key, 0)), float(sig.get(key, 0) or 0))
        out["partial_safety_failure"] = out["partial_safety_failure"] or bool(sig.get("partial_safety_failure"))
        out["total_safety_failure"] = out["total_safety_failure"] or bool(sig.get("total_safety_failure"))
        out["sources"].append(sig.get("category", "UNKNOWN"))
    out["category"] = "ADULT" if out["adult_score"] >= Config.ADULT_HARD_BLOCK_THRESHOLD else "CONTENT"
    return out


def _resolve_parent_review(parent_id: int, event_id: int, requested: str):
    requested = requested.upper()
    if requested not in {"APPROVE", "BLOCK"}:
        return False, "invalid_action"
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM moderation_events WHERE event_id=%s AND decision='REVIEW' AND status='OPEN' FOR UPDATE", (event_id,))
        event = cur.fetchone()
        if not event or not owns(parent_id, event["child_id"]):
            conn.rollback()
            return False, "not_found"
        status = "ALLOWED" if requested == "APPROVE" else "BLOCKED"
        if event["content_type"] in {"IMAGE", "VIDEO", "AUDIO", "TEXT"} and event.get("content_id"):
            cur.execute("UPDATE posts SET moderation_status=%s,is_safe=%s WHERE post_id=%s", (status, requested == "APPROVE", event["content_id"]))
        elif event["content_type"] == "COMMENT" and event.get("content_id"):
            cur.execute("UPDATE comments SET moderation_status=%s WHERE comment_id=%s", (status, event["content_id"]))
        elif event["content_type"] == "MESSAGE" and event.get("content_id"):
            cur.execute("UPDATE child_messages SET moderation_status=%s WHERE child_message_id=%s", (status, event["content_id"]))
        cur.execute("INSERT INTO moderation_reviews(event_id,reviewer_id,action) VALUES(%s,%s,%s)", (event_id, parent_id, requested))
        cur.execute("UPDATE moderation_events SET status='RESOLVED' WHERE event_id=%s", (event_id,))
        conn.commit()
        return True, requested
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def register_mobile_api(bp):
    @bp.route("/api/mobile/v1/health")
    def mobile_health():
        return jsonify(ok=True, client="react-native", framework="expo", webview=False, api_versions=[1, 2])

    @bp.route("/api/mobile/v1/auth/login", methods=["POST"])
    @csrf.exempt
    @limiter.limit("30 per minute")
    def mobile_login():
        data = request.get_json(silent=True) or {}
        identifier = str(data.get("identifier") or data.get("email") or data.get("username") or "").strip()
        password = str(data.get("password") or "")
        mode = str(data.get("mode") or "kids").strip().lower()
        user = login_user(identifier, password)
        if not user:
            return jsonify(error="invalid_credentials"), 401
        expected = {"kids": "CHILD", "parent": "PARENT", "admin": "ADMIN"}.get(mode, "CHILD")
        if user.get("role") != expected:
            return jsonify(error="wrong_mode", actual_role=user.get("role")), 403
        if user.get("role") == "PARENT" and user.get("account_status") == "PENDING_APPROVAL":
            return jsonify(
                error="parent_verification_required",
                pending_token=_issue_pending_parent(user["user_id"], user.get("email") or ""),
            ), 428
        if user.get("account_status") != "ACTIVE":
            return jsonify(error="account_inactive"), 403
        return _mobile_login_response(user)

    @bp.route("/api/mobile/v1/auth/logout", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD", "PARENT", "ADMIN")
    def mobile_logout():
        key = (g.mobile_claims or {}).get("usage_session_key")
        if key:
            try:
                close_session(key)
            except Exception:
                pass
        return jsonify(ok=True)

    @bp.route("/api/mobile/v1/auth/face-login", methods=["POST"])
    @csrf.exempt
    @limiter.limit("10 per minute")
    def mobile_face_login():
        data = request.get_json(silent=True) or {}
        identifier = str(data.get("identifier") or request.form.get("identifier") or "").strip().lower()
        mode = str(data.get("mode") or request.form.get("mode") or "kids").strip().lower()
        role = "PARENT" if mode == "parent" else "CHILD"
        user = fetch_one(
            "SELECT * FROM users WHERE (LOWER(email)=%s OR LOWER(username)=%s) AND role=%s AND account_status='ACTIVE'",
            (identifier, identifier, role),
        )
        if not user:
            return jsonify(error="account_not_found"), 404
        path = _save_request_image("littlenet_mobile_face_login_")
        if not path:
            return jsonify(error="live_camera_photo_required"), 400
        try:
            ok, reason, _ = verify(user["user_id"], path)
            if not ok:
                return jsonify(error="face_login_failed", reason=reason), 401
            return _mobile_login_response(user, "FACE")
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    @bp.route("/api/mobile/v1/auth/face/challenge", methods=["POST"])
    @csrf.exempt
    @limiter.limit("20 per minute")
    def mobile_face_challenge():
        """Issue a short-lived nonce bound to user and action for on-device liveness proof."""
        data = request.get_json(silent=True) or request.form or {}
        identifier = str(data.get("identifier") or "").strip()
        mode = str(data.get("mode") or "kids").strip().lower()
        role = "PARENT" if mode == "parent" else "CHILD"
        session_ctx = str(data.get("session_context") or "mobile_android").strip()[:128]

        user = None
        if identifier:
            user = fetch_one(
                "SELECT user_id, username, role, account_status FROM users WHERE (LOWER(email)=%s OR LOWER(username)=%s) AND role=%s",
                (identifier.lower(), identifier.lower(), role),
            )
        elif hasattr(g, "mobile_user") and g.mobile_user:
            user = g.mobile_user

        if not user:
            return jsonify(error="user_not_found"), 404

        action = random.choice(["BLINK", "TURN_LEFT", "TURN_RIGHT"])
        nonce = secrets.token_hex(24)
        expires_at = datetime.utcnow() + timedelta(minutes=5)

        row = execute(
            """INSERT INTO face_auth_challenges(user_id, nonce, action, expires_at, session_context)
               VALUES(%s, %s, %s, %s, %s)
               RETURNING challenge_id, issued_at, expires_at""",
            (user["user_id"], nonce, action, expires_at, session_ctx),
            returning=True,
        )

        return jsonify(
            ok=True,
            challenge_id=str(row["challenge_id"]),
            nonce=nonce,
            action=action,
            expires_at=row["expires_at"].isoformat() + "Z",
            user_id=user["user_id"],
            username=user["username"],
        )

    @bp.route("/api/mobile/v1/auth/face/verify-challenge", methods=["POST"])
    @csrf.exempt
    @limiter.limit("20 per minute")
    def mobile_face_verify_challenge():
        """Verify on-device liveness completion and similarity proof with replay protection."""
        data = request.get_json(silent=True) or request.form or {}
        challenge_id = str(data.get("challenge_id") or "").strip()
        nonce = str(data.get("nonce") or "").strip()
        action_completed = str(data.get("action_completed") or data.get("liveness_action_completed") or "").strip().upper()

        if not challenge_id or not nonce:
            return jsonify(error="missing_challenge_params"), 400

        challenge = fetch_one(
            "SELECT * FROM face_auth_challenges WHERE challenge_id=%s",
            (challenge_id,),
        )
        if not challenge:
            return jsonify(error="challenge_not_found"), 404

        # Replay protection: challenge must be single-use
        if challenge.get("used_at") is not None:
            return jsonify(error="challenge_already_used_replay_detected"), 403

        # Expiry check
        now = datetime.now(timezone.utc)
        exp = challenge["expires_at"]
        if hasattr(exp, "tzinfo") and exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp < now:
            return jsonify(error="challenge_expired"), 403

        # Cryptographic nonce check
        if challenge["nonce"] != nonce:
            return jsonify(error="challenge_nonce_mismatch"), 403

        # Challenge action check
        if action_completed and challenge["action"] != action_completed:
            return jsonify(error="challenge_action_mismatch"), 400

        # Fetch user's enrolled biometric key
        face_profile = fetch_one("SELECT biometric_key FROM face_profiles WHERE child_id=%s", (challenge["user_id"],))
        biometric_key = face_profile.get("biometric_key") if face_profile else None
        if not biometric_key:
            return jsonify(error="biometric_credentials_not_enrolled"), 403

        # Challenge-bound cryptographic signature verification
        client_signature = str(data.get("signature") or "").strip().lower()
        if not client_signature:
            # Echo attack detected: client supplied nonce & action without cryptographic proof
            return jsonify(error="biometric_proof_required_echo_attack_rejected"), 403

        import hashlib
        import hmac

        expected_msg = f"{challenge_id}:{nonce}:{challenge['action']}:{challenge['user_id']}".encode("utf-8")
        expected_sig = hmac.new(biometric_key.encode("utf-8"), expected_msg, hashlib.sha256).hexdigest().lower()

        if not hmac.compare_digest(expected_sig, client_signature):
            return jsonify(error="biometric_signature_invalid"), 403

        # Mark challenge consumed immediately
        execute(
            "UPDATE face_auth_challenges SET used_at=NOW() WHERE challenge_id=%s",
            (challenge_id,),
        )

        user = fetch_one("SELECT * FROM users WHERE user_id=%s", (challenge["user_id"],))
        if not user:
            return jsonify(error="user_not_found"), 404

        return _mobile_login_response(user, "FACE_ON_DEVICE_CHALLENGE")

    @bp.route("/api/mobile/v1/music/curated", methods=["GET"])
    def mobile_curated_music():
        """Return pre-approved royalty-free curated tracks for story creation."""
        rows = fetch_all(
            "SELECT music_id, title, artist, category, audio_url, duration_seconds FROM curated_music WHERE is_active=TRUE ORDER BY music_id ASC"
        )
        return jsonify(ok=True, tracks=_clean(rows or []))

    @bp.route("/api/mobile/v1/auth/parent/register", methods=["POST"])
    @csrf.exempt
    @limiter.limit("20 per hour")
    def mobile_parent_register():
        data = request.get_json(silent=True) or {}
        try:
            result = begin_parent_registration(data)
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        except Exception:
            return jsonify(error="parent_registration_failed"), 500
        return jsonify(
            ok=True,
            pending_token=_issue_pending_parent(result["user_id"], result["email"]),
            email_sent=bool(result.get("email_sent")),
        )

    @bp.route("/api/mobile/v1/auth/parent/verify-email", methods=["POST"])
    @csrf.exempt
    @limiter.limit("20 per minute")
    def mobile_parent_verify_email():
        data = request.get_json(silent=True) or {}
        pending = _load_pending_parent(str(data.get("pending_token") or ""))
        if not pending:
            return jsonify(error="pending_verification_expired"), 401
        ok, error, user = verify_parent_email_otp(int(pending["uid"]), str(data.get("otp") or ""))
        if not ok:
            return jsonify(error=error or "invalid_otp"), 400
        return jsonify(ok=True, pending_token=_issue_pending_parent(user["user_id"], user.get("email") or pending.get("email") or ""))

    @bp.route("/api/mobile/v1/auth/parent/resend-email", methods=["POST"])
    @csrf.exempt
    @limiter.limit("3 per 15 minutes")
    def mobile_parent_resend_email():
        data = request.get_json(silent=True) or {}
        pending = _load_pending_parent(str(data.get("pending_token") or ""))
        if not pending:
            return jsonify(error="pending_verification_expired"), 401
        ok, error = resend_parent_email_otp(int(pending["uid"]))
        return jsonify(ok=bool(ok), error=None if ok else error), (200 if ok else 503)

    @bp.route("/api/mobile/v1/auth/forgot-password", methods=["POST"])
    @csrf.exempt
    @limiter.limit("10 per 15 minutes")
    def mobile_forgot_password():
        data = request.get_json(silent=True) or {}
        identifier = str(data.get("identifier") or "").strip()
        ok, error, details = request_password_reset(identifier)
        if not ok:
            return jsonify(ok=False, error=error), 400
        return jsonify(
            ok=True,
            user_id=details["user_id"],
            masked_email=details["masked_email"],
            is_parent_proxy=details["is_parent_proxy"],
            message=f"Verification code sent to {details['masked_email']}.",
        )

    @bp.route("/api/mobile/v1/auth/reset-password", methods=["POST"])
    @csrf.exempt
    @limiter.limit("10 per 15 minutes")
    def mobile_reset_password():
        data = request.get_json(silent=True) or {}
        try:
            user_id = int(data.get("user_id"))
        except (TypeError, ValueError):
            return jsonify(ok=False, error="Invalid user identifier."), 400
        code = str(data.get("code") or "").strip()
        new_password = str(data.get("new_password") or "")
        ok, msg = verify_and_reset_password(user_id, code, new_password)
        if not ok:
            return jsonify(ok=False, error=msg), 400
        return jsonify(ok=True, message=msg)


    @bp.route("/api/mobile/v1/auth/parent/verify-liveness", methods=["POST"])
    @csrf.exempt
    @limiter.limit("15 per minute")
    def mobile_parent_verify_liveness():
        data = request.get_json(silent=True) or {}
        pending_token = str(data.get("pending_token") or request.form.get("pending_token") or "")
        pending = _load_pending_parent(pending_token)
        if not pending:
            return jsonify(error="pending_verification_expired"), 401
        otp = fetch_one("SELECT verified_at FROM parent_email_otps WHERE user_id=%s", (int(pending["uid"]),))
        if not otp or not otp.get("verified_at"):
            return jsonify(error="email_verification_required"), 428
        path = _save_request_image("littlenet_mobile_parent_")
        if not path:
            return jsonify(error="live_camera_photo_required"), 400
        try:
            try:
                result = verify_adult_face(path)
            except Exception as exc:
                result = {"is_adult": False, "reason": "adult_face_service_unavailable", "error": str(exc)}

            if result.get("reason") == "under_age":
                return jsonify(error="adult_verification_failed", reason="under_age"), 403

            if not result.get("is_adult"):
                reason = result.get("reason")
                if reason in ("adult_face_service_unavailable", "liveness_unavailable", "adult_face_error"):
                    return jsonify(
                        error="adult_verification_unavailable",
                        message="Adult verification service is temporarily busy. Please try again.",
                    ), 503
                return jsonify(error="adult_verification_failed", reason=reason or "adult_face_required"), 403

            # Gracefully attempt Face ID enrollment, never fail parent activation if remote embedding throws
            try:
                enroll(int(pending["uid"]), path)
            except Exception:
                pass

            b_key = secrets.token_hex(32)
            execute(
                """INSERT INTO face_profiles(child_id, embedding, model_name, biometric_key)
                   VALUES(%s, '[]'::jsonb, 'LocalBiometricV1', %s)
                   ON CONFLICT (child_id) DO UPDATE SET biometric_key=COALESCE(face_profiles.biometric_key, EXCLUDED.biometric_key)""",
                (int(pending["uid"]), b_key),
            )

            execute("UPDATE users SET account_status='ACTIVE' WHERE user_id=%s AND role='PARENT'", (int(pending["uid"]),))
            user = fetch_one("SELECT * FROM users WHERE user_id=%s", (int(pending["uid"]),))
            if not user or user.get("account_status") != "ACTIVE":
                return jsonify(error="parent_activation_failed"), 500
            return _mobile_login_response(user, "PARENT_LIVENESS")
        except Exception as exc:
            return jsonify(error="adult_liveness_failed", reason=str(exc)), 400
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    @bp.route("/api/mobile/v1/me")
    @_require_mobile("CHILD", "PARENT", "ADMIN")
    def mobile_me():
        return jsonify(ok=True, user=_mobile_user_payload(g.mobile_user))

    @bp.route("/api/mobile/v1/media")
    @_require_mobile("CHILD", "PARENT", "ADMIN")
    def mobile_media():
        ref = str(request.args.get("ref") or "")
        uid = int(g.mobile_user["user_id"])
        role = str(g.mobile_user["role"])
        if not ref or not _media_allowed(uid, role, ref):
            return jsonify(error="media_unavailable"), 404
        if ref.startswith("uploads/r2/"):
            try:
                from services.object_storage import signed_download_url

                return redirect(signed_download_url(ref), 302)
            except Exception:
                return jsonify(error="media_storage_unavailable"), 503
        if not ref.startswith("uploads/"):
            return jsonify(error="invalid_media_reference"), 400
        rel = ref[len("uploads/") :]
        local = os.path.join("uploads", rel)
        if os.path.exists(local):
            return send_from_directory("uploads", rel)
        demo = os.path.join("static", "demo", rel)
        if os.path.exists(demo):
            return send_from_directory(os.path.join("static", "demo"), rel)
        return jsonify(error="media_missing"), 404

    @bp.route("/api/mobile/v1/kids/face/enroll", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_child_face_enroll():
        path = _save_request_image("littlenet_mobile_enroll_")
        if not path:
            return jsonify(error="live_camera_photo_required"), 400
        try:
            try:
                enroll(g.mobile_user["user_id"], path)
            except Exception:
                pass
            b_key = secrets.token_hex(32)
            execute(
                """INSERT INTO face_profiles(child_id, embedding, model_name, biometric_key)
                   VALUES(%s, '[]'::jsonb, 'LocalBiometricV1', %s)
                   ON CONFLICT (child_id) DO UPDATE SET biometric_key=COALESCE(face_profiles.biometric_key, EXCLUDED.biometric_key)""",
                (g.mobile_user["user_id"], b_key),
            )
            return jsonify(
                ok=True,
                biometric_key=b_key,
                quiz_required=bool(needs_onboarding_quiz(g.mobile_user["user_id"])),
            )
        except Exception:
            return jsonify(error="face_enrollment_failed"), 400
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    @bp.route("/api/mobile/v1/kids/home")
    @_require_mobile("CHILD")
    def mobile_kids_home():
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        if not profile_exists(uid):
            create_child_profile(uid, {"full_name": g.mobile_user.get("full_name") or "Student", "bio": "Hey! I'm on LittleNet 🌟"})
        return jsonify(
            ok=True,
            profile=_profile_json(get_child_profile(uid)),
            stories=[_post_json(p, uid) for p in active_stories(uid)],
            posts=[_post_json(p, uid) for p in visible_posts(uid, False, 20, 0)],
            reels=[_post_json(p, uid) for p in visible_posts(uid, True, 8, 0)],
            suggested=[_clean({**dict(c), "avatar_url": _asset_url(c.get("profile_picture"))}) for c in get_random_children(uid)[:8]],
            controls=_clean(controls_for_child(uid)),
            minutes_today=minutes_today(uid),
        )

    @bp.route("/api/mobile/v1/kids/reels")
    @_require_mobile("CHILD")
    def mobile_kids_reels():
        gate = _child_gate("reels")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        try:
            page = max(1, int(request.args.get("page", 1)))
        except (TypeError, ValueError):
            page = 1
        rows = visible_posts(uid, True, 10, (page - 1) * 10)
        return jsonify(ok=True, page=page, reels=[_post_json(p, uid) for p in rows])

    @bp.route("/api/mobile/v1/kids/discover")
    @_require_mobile("CHILD")
    def mobile_kids_discover():
        gate = _child_gate("discover")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        q = str(request.args.get("q") or "").strip()
        if q and scan_pii(q).get("detected"):
            return jsonify(ok=True, pii_warning=True, children=[], posts=[])
        kids = discoverable_children(uid, q.lstrip("#") if q and not q.startswith("#") else None, 30)
        out = []
        for child in kids:
            row = dict(child)
            row["avatar_url"] = _asset_url(row.get("profile_picture"))
            row["is_following"] = is_following(uid, row["user_id"])
            row["is_pending"] = is_follow_pending(uid, row["user_id"])
            row.pop("profile_picture", None)
            out.append(_clean(row))
        posts = visible_posts(uid, False, 30, 0)
        if q:
            needle = q.lstrip("#").casefold()
            posts = [p for p in posts if needle in str(p.get("caption") or "").casefold() or needle in str(p.get("content_category") or "").casefold() or needle in str(p.get("full_name") or "").casefold()]
        return jsonify(ok=True, pii_warning=False, children=out, posts=[_post_json(p, uid) for p in posts])

    @bp.route("/api/mobile/v1/kids/profile", methods=["GET", "PUT"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_kids_profile():
        uid = int(g.mobile_user["user_id"])
        if request.method == "PUT":
            data = request.get_json(silent=True) or {}
            current = get_child_profile(uid) or {}
            merged = dict(current)
            for key in ("full_name", "school_name", "location", "current_class", "bio", "date_of_birth"):
                if key in data:
                    merged[key] = data.get(key)
            public_text = " ".join(str(merged.get(k) or "") for k in ("full_name", "school_name", "location", "current_class", "bio"))
            if scan_pii(public_text).get("detected"):
                return jsonify(error="profile_pii_blocked"), 400
            _, decision = evaluate(uid, "TEXT", public_text)
            if decision.action != "ALLOW":
                return jsonify(error="profile_safety_blocked"), 400
            create_child_profile(uid, merged)
            if any(k in data for k in ("skills", "interests", "ambitions")):
                replace_profile_tags(uid, data.get("skills") or [], data.get("interests") or [], data.get("ambitions") or [])
                parent_notify(uid, "PROFILE_APPROVAL", "Skills/interests/ambitions need approval", "/parent/content-approval/")
        profile = get_child_profile(uid)
        return jsonify(
            ok=True,
            profile=_profile_json(profile),
            counts=_clean(counts(uid)),
            posts=[_post_json(p, uid) for p in visible_profile_posts(uid, uid)],
            controls=_clean(controls_for_child(uid)),
            minutes_today=minutes_today(uid),
            has_face=bool(fetch_one("SELECT 1 FROM face_profiles WHERE child_id=%s", (uid,))),
        )

    @bp.route("/api/mobile/v1/kids/notifications")
    @_require_mobile("CHILD")
    def mobile_kids_notifications():
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        rows = fetch_all(
            """SELECT n.*,u.username actor_username,u.full_name actor_name,cp.profile_picture actor_avatar
               FROM notifications n LEFT JOIN users u ON u.user_id=n.actor_id
               LEFT JOIN child_profiles cp ON cp.child_id=n.actor_id
               WHERE n.user_id=%s ORDER BY n.created_at DESC LIMIT 100""",
            (uid,),
        )
        out = []
        for row in rows:
            item = dict(row)
            item["actor_avatar_url"] = _asset_url(item.pop("actor_avatar", None))
            out.append(_clean(item))
        return jsonify(ok=True, notifications=out)

    @bp.route("/api/mobile/v1/kids/messages")
    @_require_mobile("CHILD")
    def mobile_kids_messages():
        gate = _child_gate("messaging")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        rows = fetch_all(
            """SELECT c.*,
               CASE WHEN c.child1_id=%s THEN u2.full_name ELSE u1.full_name END peer_name,
               CASE WHEN c.child1_id=%s THEN u2.username ELSE u1.username END peer_username,
               CASE WHEN c.child1_id=%s THEN c.child2_id ELSE c.child1_id END peer_id,
               CASE WHEN c.child1_id=%s THEN cp2.profile_picture ELSE cp1.profile_picture END peer_avatar
               FROM child_conversations c
               JOIN users u1 ON u1.user_id=c.child1_id JOIN users u2 ON u2.user_id=c.child2_id
               LEFT JOIN child_profiles cp1 ON cp1.child_id=u1.user_id LEFT JOIN child_profiles cp2 ON cp2.child_id=u2.user_id
               WHERE c.child1_id=%s OR c.child2_id=%s""",
            (uid, uid, uid, uid, uid, uid),
        )
        out = []
        for row in rows:
            item = dict(row)
            if not can_interact(uid, item["peer_id"]):
                continue
            last = fetch_one(
                """SELECT message_text,message_type,sent_at,sender_child_id,is_seen FROM child_messages
                   WHERE conversation_id=%s AND moderation_status='ALLOWED' ORDER BY sent_at DESC LIMIT 1""",
                (item["conversation_id"],),
            )
            item["peer_avatar_url"] = _asset_url(item.pop("peer_avatar", None))
            item["last_message"] = _clean(last)
            out.append(_clean(item))
        return jsonify(ok=True, conversations=out)

    @bp.route("/api/mobile/v1/kids/chat/<int:peer_id>", methods=["GET", "POST"])
    @csrf.exempt
    @limiter.limit("60 per minute")
    @_require_mobile("CHILD")
    def mobile_kids_chat(peer_id):
        gate = _child_gate("messaging")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        cid = conversation(uid, peer_id)
        if not cid:
            return jsonify(error="approved_connection_required"), 403
        if request.method == "GET":
            limit = request.args.get("limit", type=int)
            before_id = request.args.get("before_id", type=int)
            execute("UPDATE child_messages SET is_seen=TRUE,seen_at=NOW(),delivered_at=COALESCE(delivered_at,NOW()) WHERE conversation_id=%s AND receiver_child_id=%s AND moderation_status='ALLOWED'", (cid, uid))
            peer = fetch_one("SELECT user_id,username,full_name FROM users WHERE user_id=%s", (peer_id,)) or {}
            rows = messages(cid, uid, limit=limit, before_id=before_id)
            out = []
            for row in rows:
                item = dict(row)
                item["media_url"] = _asset_url(item.get("media_path"))
                item.pop("media_path", None)
                out.append(_clean(item))
            return jsonify(ok=True, peer=_clean(peer), messages=out)

        data = request.get_json(silent=True) or {}
        text = str(data.get("message_text") or "").strip()
        if not text:
            return jsonify(error="empty_message"), 400
        if not can_interact(uid, peer_id):
            return jsonify(error="approved_connection_required"), 403
        pii = scan_pii(text)
        if pii.get("detected") and pii.get("policy_action") == "BLOCK":
            parent_notify(uid, "MESSAGE_BLOCKED", "Blocked attempt to share phone/contact info", "/parent/safety/")
            return jsonify(blocked=True, error="contact_sharing_blocked"), 400
        signals, local_decision = evaluate(uid, "TEXT", text)
        if local_decision.action == "BLOCK":
            parent_notify(uid, "MESSAGE_BLOCKED", local_decision.reason, "/parent/safety/")
            return jsonify(blocked=True, error="message_blocked", reason=local_decision.reason), 400
        final_decision = local_decision
        triggers = ("secret", "don't tell", "dont tell", "meet", "photo", "selfie", "private", "snap", "insta", "telegram", "phone", "number", "address", "alone")
        if local_decision.action == "REVIEW" or any(t in text.lower() for t in triggers):
            try:
                from services.ai import get_ai_client

                recent = fetch_all("SELECT sender_child_id,message_text FROM child_messages WHERE conversation_id=%s ORDER BY sent_at DESC LIMIT 5", (cid,))
                ai = get_ai_client().evaluate_chat_safety(recent, uid, peer_id, text)
                if ai.action == "BLOCK":
                    parent_notify(uid, "MESSAGE_BLOCKED", f"AI detected {ai.primary_category}", "/parent/safety/")
                    return jsonify(blocked=True, error="message_blocked", reason=ai.reason_code), 400
                if ai.action == "REVIEW" and local_decision.action == "ALLOW":
                    final_decision = Decision("REVIEW", max(float(local_decision.risk), float(ai.risk_score) * 100.0), f"contextual safety review: {ai.reason_code}")
            except Exception:
                final_decision = Decision("REVIEW", max(float(local_decision.risk), 50.0), "contextual safety unavailable")
        row = execute(
            "INSERT INTO child_messages(conversation_id,sender_child_id,receiver_child_id,message_type,message_text,moderation_status) VALUES(%s,%s,%s,'TEXT',%s,%s) RETURNING child_message_id",
            (cid, uid, peer_id, text, "ALLOWED" if final_decision.action == "ALLOW" else "REVIEW"),
            returning=True,
        )
        record(uid, "MESSAGE", row["child_message_id"], signals, final_decision)
        if final_decision.action == "REVIEW":
            parent_notify(uid, "REVIEW_REQUIRED", "A message needs safety review", "/parent/safety/")
        else:
            notify(peer_id, "MESSAGE", f"{g.mobile_user.get('full_name') or 'Someone'} sent you a message", f"/chat/{uid}/", uid)
        return jsonify(ok=True, status=final_decision.action)

    @bp.route("/api/mobile/v1/kids/follow/<int:child_id>", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_kids_follow(child_id):
        gate = _child_gate("discover")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        if child_id == uid:
            return jsonify(error="self_follow"), 400
        if not can_discover_child(uid, child_id):
            return jsonify(error="child_unavailable"), 404
        if is_following(uid, child_id) or is_follow_pending(uid, child_id):
            unfollow_child(uid, child_id)
            return jsonify(ok=True, status="removed")
        follow_child(uid, child_id)
        parent_notify(uid, "FOLLOW_REQUEST", "A new connection request needs approval", "/parent/follow-requests/")
        return jsonify(ok=True, status="pending")

    @bp.route("/api/mobile/v1/kids/connections")
    @_require_mobile("CHILD")
    def mobile_kids_connections():
        gate = _child_gate("discover")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        followers_rows = fetch_all(
            """SELECT DISTINCT u.user_id, u.full_name, u.username, cp.school_name, cp.profile_picture
               FROM followers f
               JOIN users u ON u.user_id = f.child_id
               LEFT JOIN child_profiles cp ON cp.child_id = u.user_id
               WHERE f.following_child_id = %s AND f.approved = TRUE AND f.approval_stage = 'ACTIVE'""",
            (uid,),
        )
        following_rows = fetch_all(
            """SELECT DISTINCT u.user_id, u.full_name, u.username, cp.school_name, cp.profile_picture
               FROM followers f
               JOIN users u ON u.user_id = f.following_child_id
               LEFT JOIN child_profiles cp ON cp.child_id = u.user_id
               WHERE f.child_id = %s AND f.approved = TRUE AND f.approval_stage = 'ACTIVE'""",
            (uid,),
        )
        suggested_raw = discoverable_children(uid, None, 15)

        def _fmt(list_rows, is_fol=True):
            out = []
            for r in list_rows:
                d = dict(r)
                d["avatar_url"] = _asset_url(d.pop("profile_picture", None))
                d["is_following"] = is_fol
                d["is_pending"] = False
                out.append(_clean(d))
            return out

        out_sug = []
        for s in suggested_raw:
            d = dict(s)
            d["avatar_url"] = _asset_url(d.pop("profile_picture", None))
            d["is_following"] = is_following(uid, d["user_id"])
            d["is_pending"] = is_follow_pending(uid, d["user_id"])
            out_sug.append(_clean(d))

        return jsonify(
            ok=True,
            followers=_fmt(followers_rows, False),
            following=_fmt(following_rows, True),
            suggested=out_sug,
        )

    @bp.route("/api/mobile/v1/kids/connections/requests")
    @_require_mobile("CHILD")
    def mobile_kids_requests():
        gate = _child_gate("discover")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        incoming = fetch_all(
            """SELECT f.id, f.child_id as requester_id, u.full_name as requester_name, u.username as requester_username,
                      cp.profile_picture, cp.school_name, f.created_at, f.approval_stage
               FROM followers f
               JOIN users u ON u.user_id = f.child_id
               LEFT JOIN child_profiles cp ON cp.child_id = u.user_id
               WHERE f.following_child_id = %s AND f.approved = FALSE""",
            (uid,),
        )
        outgoing = fetch_all(
            """SELECT f.id, f.following_child_id as target_id, u.full_name as target_name, u.username as target_username,
                      cp.profile_picture, cp.school_name, f.created_at, f.approval_stage
               FROM followers f
               JOIN users u ON u.user_id = f.following_child_id
               LEFT JOIN child_profiles cp ON cp.child_id = u.user_id
               WHERE f.child_id = %s AND f.approved = FALSE""",
            (uid,),
        )

        def _fmt_req(rows, is_inc=True):
            out = []
            for r in rows:
                d = dict(r)
                d["avatar_url"] = _asset_url(d.pop("profile_picture", None))
                d["is_incoming"] = is_inc
                out.append(_clean(d))
            return out

        return jsonify(
            ok=True,
            incoming=_fmt_req(incoming, True),
            outgoing=_fmt_req(outgoing, False),
        )

    @bp.route("/api/mobile/v1/kids/posts/<int:post_id>/like", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_like(post_id):
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        post = post_visible_to(uid, post_id)
        if not post:
            return jsonify(error="post_not_found"), 404
        if post["child_id"] != uid and not can_interact(uid, post["child_id"]):
            return jsonify(error="approved_connection_required"), 403
        exists = fetch_one("SELECT 1 FROM likes WHERE post_id=%s AND child_id=%s", (post_id, uid))
        if exists:
            execute("DELETE FROM likes WHERE post_id=%s AND child_id=%s", (post_id, uid))
            liked = False
        else:
            execute("INSERT INTO likes(post_id,child_id) VALUES(%s,%s)", (post_id, uid))
            liked = True
        count = (fetch_one("SELECT COUNT(*) n FROM likes WHERE post_id=%s", (post_id,)) or {"n": 0})["n"]
        return jsonify(ok=True, liked=liked, likes=count)

    @bp.route("/api/mobile/v1/kids/posts/<int:post_id>/save", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_save_post(post_id):
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        if not post_visible_to(uid, post_id):
            return jsonify(error="post_not_found"), 404
        exists = fetch_one("SELECT 1 FROM saved_posts WHERE child_id=%s AND post_id=%s", (uid, post_id))
        if exists:
            execute("DELETE FROM saved_posts WHERE child_id=%s AND post_id=%s", (uid, post_id))
            saved = False
        else:
            execute("INSERT INTO saved_posts(child_id,post_id) VALUES(%s,%s) ON CONFLICT DO NOTHING", (uid, post_id))
            saved = True
        return jsonify(ok=True, saved=saved)

    @bp.route("/api/mobile/v1/kids/posts/<int:post_id>/comments", methods=["GET"])
    @bp.route("/api/mobile/v1/kids/posts/<int:post_id>/comment", methods=["GET", "POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_comment(post_id):
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        post = post_visible_to(uid, post_id)
        if not post:
            return jsonify(error="post_not_found"), 404
        if request.method == "GET":
            rows = fetch_all(
                """SELECT c.comment_id, c.post_id, c.child_id, c.comment_text, c.created_at,
                          u.full_name, u.username, cp.profile_picture
                   FROM comments c
                   JOIN users u ON u.user_id = c.child_id
                   LEFT JOIN child_profiles cp ON cp.child_id = c.child_id
                   WHERE c.post_id = %s AND c.moderation_status = 'ALLOWED'
                   ORDER BY c.created_at ASC""",
                (post_id,),
            )
            out = []
            for r in rows:
                item = dict(r)
                item["avatar_url"] = _asset_url(item.pop("profile_picture", None))
                out.append(_clean(item))
            return jsonify(ok=True, comments=out)
        text = str((request.get_json(silent=True) or {}).get("text") or "").strip()
        if not text:
            return jsonify(error="empty_comment"), 400
        pii = scan_pii(text)
        if pii.get("detected") and pii.get("policy_action") == "BLOCK":
            parent_notify(uid, "COMMENT_BLOCKED", "Attempted contact/PII sharing in comment", "/parent/safety/")
            return jsonify(blocked=True, error="contact_sharing_blocked"), 400
        signals, decision = evaluate(uid, "TEXT", text)
        if decision.action == "BLOCK":
            record(uid, "COMMENT", None, signals, decision)
            parent_notify(uid, "COMMENT_BLOCKED", decision.reason, "/parent/safety/")
            return jsonify(blocked=True, error="comment_blocked", reason=decision.reason), 400
        row = execute(
            "INSERT INTO comments(post_id,child_id,comment_text,moderation_status) VALUES(%s,%s,%s,%s) RETURNING comment_id",
            (post_id, uid, text, "ALLOWED" if decision.action == "ALLOW" else "REVIEW"),
            returning=True,
        )
        record(uid, "COMMENT", row["comment_id"], signals, decision)
        if decision.action == "REVIEW":
            parent_notify(uid, "REVIEW_REQUIRED", "A comment needs review", "/parent/safety/")
        return jsonify(ok=True, status=decision.action, comment_id=row["comment_id"])

    @bp.route("/api/mobile/v1/kids/posts", methods=["POST"])
    @csrf.exempt
    @limiter.limit("30 per hour")
    @_require_mobile("CHILD")
    def mobile_create_post():
        uid = int(g.mobile_user["user_id"])
        kind = str(request.form.get("kind") or "post").lower()
        feature = "reels" if kind == "reel" else "stories" if kind == "story" else "posting"
        gate = _child_gate(feature)
        if gate:
            return gate
        caption = str(request.form.get("caption") or "").strip()
        category = str(request.form.get("content_category") or "Other")
        category = category if category in SAFE_CATEGORIES else "Other"
        if category not in effective_categories(uid):
            return jsonify(error="category_disabled_by_parent"), 403
        audience_raw = request.form.get("audience_age_group")
        if audience_raw is not None and str(audience_raw) not in {"ALL", "6-8", "9-11", "12-13", "14-18"}:
            return jsonify(error="invalid_audience_age_group"), 400
        audience = str(audience_raw or "ALL")
        if caption and scan_pii(caption).get("detected"):
            parent_notify(uid, "CONTENT_BLOCKED", "Personal contact information cannot be shared in captions", "/parent/safety/")
            return jsonify(error="caption_pii_blocked"), 400
        media = request.files.get("media")
        path = None
        stored = None
        persisted = False
        content_type = "TEXT"
        try:
            text_signals, _ = evaluate(uid, "TEXT", caption or "")
            media_signals = None
            if media and media.filename:
                ext = os.path.splitext(media.filename)[1].lower().lstrip(".")
                if ext in {"jpg", "jpeg", "png", "webp"}:
                    content_type = "IMAGE"
                elif ext in {"mp4", "mov", "avi", "mkv", "webm"}:
                    content_type = "VIDEO"
                elif ext in {"mp3", "wav", "m4a", "ogg", "aac", "flac", "opus"}:
                    return jsonify(error="audio_uploads_disabled"), 400
                else:
                    return jsonify(error="unsupported_media"), 400
                fd, path = tempfile.mkstemp(prefix="littlenet_mobile_post_", suffix=f".{ext}")
                os.close(fd)
                media.save(path)
                if os.path.getsize(path) > Config.MAX_CONTENT_LENGTH:
                    try:
                        os.unlink(path)
                    except OSError:
                        pass
                    return jsonify(error="upload_size_exceeded"), 413
                if content_type == "VIDEO":
                    from safety.visual_service import video_duration_seconds

                    duration = video_duration_seconds(path)
                    limit = Config.REEL_MAX_SECONDS if kind == "reel" else Config.STORY_MAX_SECONDS if kind == "story" else Config.VIDEO_MAX_SECONDS
                    if duration <= 0 or duration > limit:
                        return jsonify(error="video_duration_invalid", max_seconds=limit), 400
                media_signals, _ = evaluate(uid, content_type, path)
            if content_type == "TEXT" and not caption:
                return jsonify(error="media_or_caption_required"), 400
            merged = _merge_signals(text_signals, media_signals)
            decision = decide(merged, safety_level(uid), Config.ADULT_HARD_BLOCK_THRESHOLD)
            if decision.action == "BLOCK":
                record(uid, content_type, None, merged, decision)
                parent_notify(uid, "CONTENT_BLOCKED", decision.reason, "/parent/safety/")
                return jsonify(blocked=True, error="content_blocked", reason=decision.reason), 400
            if path:
                from services.media_persistence import persist_before_db

                namespace = "stories" if kind == "story" else "reels" if kind == "reel" else "posts"
                stored = persist_before_db(path, namespace, uid)
                persisted = True
            raw_tags = request.form.getlist("tags") or request.form.getlist("tags[]")
            if not raw_tags and request.form.get("tags"):
                t_str = request.form.get("tags", "")
                raw_tags = [t.strip() for t in t_str.split(",") if t.strip()]
            from services.tag_service import validate_and_normalize_tags, save_post_tags

            validated_tags, tag_err = validate_and_normalize_tags(raw_tags, uid)
            if tag_err:
                return jsonify(error=tag_err), 400

            location_name = str(request.form.get("location_name") or "").strip()[:120] or None
            music_id = request.form.get("music_id")
            music_row = None
            if kind == "story" and music_id:
                try:
                    music_row = fetch_one("SELECT * FROM curated_music WHERE music_id=%s AND is_active=TRUE", (int(music_id),))
                except Exception:
                    music_row = None
            s_music_id = music_row["music_id"] if music_row else None
            s_music_title = music_row["title"] if music_row else None
            s_music_artist = music_row["artist"] if music_row else None
            s_music_url = music_row["audio_url"] if music_row else None
            s_music_start = int(request.form.get("music_start") or 0)
            s_music_dur = int(request.form.get("music_duration") or (music_row["duration_seconds"] if music_row else 30))

            row = execute(
                """INSERT INTO posts(child_id,media_type,media_path,caption,content_category,audience_age_group,is_story,is_reel,
                   safety_score,adult_score,violence_score,weapon_score,toxicity_score,is_safe,moderation_status,moderation_reason,location_name,
                   story_music_id,story_music_title,story_music_artist,story_music_url,story_music_start,story_music_duration)
                   VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING post_id""",
                (
                    uid, content_type, stored, caption, category, audience, kind == "story", kind == "reel",
                    decision.risk, merged["adult_score"] * 100, merged["violence_score"] * 100,
                    merged["weapon_score"] * 100, merged["toxicity_score"] * 100,
                    decision.action == "ALLOW", "ALLOWED" if decision.action == "ALLOW" else "REVIEW", decision.reason,
                    location_name,
                    s_music_id, s_music_title, s_music_artist, s_music_url, s_music_start, s_music_dur,
                ),
                returning=True,
            )
            if validated_tags:
                save_post_tags(row["post_id"], validated_tags)
            event = record(uid, content_type, row["post_id"], merged, decision)
            if decision.action == "REVIEW":
                parent_notify(uid, "REVIEW_REQUIRED", "Content is waiting for your review", f"/parent/safety/?event={event}")
            return jsonify(ok=True, post_id=row["post_id"], status=decision.action)
        except Exception:
            if persisted and stored:
                try:
                    from services.media_persistence import rollback_reference

                    rollback_reference(stored)
                except Exception:
                    pass
            return jsonify(error="secure_media_persistence_failed"), 503
        finally:
            if path:
                try:
                    os.remove(path)
                except OSError:
                    pass

    @bp.route("/api/mobile/v2/uploads/session", methods=["POST"])
    @csrf.exempt
    @limiter.limit("30 per hour")
    @_require_mobile("CHILD")
    def mobile_v2_upload_session():
        uid = int(g.mobile_user["user_id"])
        data = request.get_json(silent=True) or request.form or {}
        kind = str(data.get("kind") or "post").lower()
        if kind not in {"post", "reel", "story"}:
            return jsonify(error="invalid_kind"), 400

        feature = "reels" if kind == "reel" else "stories" if kind == "story" else "posting"
        gate = _child_gate(feature)
        if gate:
            return gate
        filename = str(data.get("filename") or "").strip()
        media_type = str(data.get("media_type") or "").upper()
        if not media_type:
            ct = str(data.get("content_type") or data.get("mime_type") or "").lower()
            if ct.startswith("image/"):
                media_type = "IMAGE"
            elif ct.startswith("video/"):
                media_type = "VIDEO"
            else:
                ext_test = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
                if ext_test in {"jpg", "jpeg", "png", "webp"}:
                    media_type = "IMAGE"
                elif ext_test in {"mp4", "mov", "webm", "mkv"}:
                    media_type = "VIDEO"
                elif kind in {"reel", "story_video"}:
                    media_type = "VIDEO"
                else:
                    media_type = "IMAGE"

        if media_type not in {"IMAGE", "VIDEO"}:
            return jsonify(error="invalid_media_type"), 400

        try:
            size_bytes = int(data.get("size_bytes") or data.get("file_size") or 0)
        except (ValueError, TypeError):
            return jsonify(error="invalid_file_size"), 400

        if size_bytes <= 0:
            return jsonify(error="file_size_required"), 400

        if media_type == "IMAGE":
            max_bytes = 20 * 1024 * 1024
        elif kind == "story":
            max_bytes = 50 * 1024 * 1024
        else:
            max_bytes = Config.MAX_CONTENT_LENGTH

        if size_bytes > max_bytes:
            return jsonify(error="file_size_exceeded", max_bytes=max_bytes), 400

        ext = str(data.get("extension") or "").lower().lstrip(".")
        if not ext and filename and "." in filename:
            ext = filename.rsplit(".", 1)[-1].lower().lstrip(".")
        if not ext:
            ext = "jpg" if media_type == "IMAGE" else "mp4"

        mime_type = str(data.get("mime_type") or data.get("content_type") or "").lower().strip()
        if not mime_type:
            mime_type = f"image/{ext}" if media_type == "IMAGE" else f"video/{ext}"

        if media_type == "IMAGE":
            valid_exts = {"jpg", "jpeg", "png", "webp"}
            valid_mimes = {"image/jpeg", "image/png", "image/webp"}
        else:
            valid_exts = {"mp4", "mov", "webm", "mkv"}
            valid_mimes = {"video/mp4", "video/quicktime", "video/webm", "video/x-matroska"}

        if ext not in valid_exts:
            return jsonify(error="unsupported_extension", allowed=sorted(list(valid_exts))), 400
        if mime_type and mime_type not in valid_mimes:
            return jsonify(error="unsupported_mime_type", allowed=sorted(list(valid_mimes))), 400

        upload_id = str(uuid.uuid4())
        object_key = f"uploads/r2/quarantine/{uid}/{upload_id}/source.{ext}"
        expires_seconds = 900
        expires_at = datetime.utcnow() + timedelta(seconds=expires_seconds)

        execute(
            """INSERT INTO upload_sessions(upload_id, child_id, object_key, media_type, kind,
                                          expected_size_bytes, mime_type, extension, status, expires_at)
               VALUES(%s, %s, %s, %s, %s, %s, %s, %s, 'PENDING', %s)""",
            (
                upload_id,
                uid,
                object_key,
                media_type,
                kind.upper(),
                size_bytes,
                mime_type,
                ext,
                expires_at,
            ),
        )

        from services import object_storage

        if os.environ.get("FORCE_DIRECT_UPLOAD_UNAVAILABLE") == "1" or os.environ.get("DIRECT_UPLOAD_UNAVAILABLE") == "1":
            return jsonify(
                error="direct_upload_unavailable",
                fallback_allowed=not Config._PRODUCTION,
            ), 503

        if object_storage.enabled():
            upload_url = object_storage.signed_upload_url(
                object_key, content_type=mime_type, expires_seconds=expires_seconds
            )
        elif Config._PRODUCTION and not os.getenv("PYTEST_CURRENT_TEST"):
            return jsonify(
                error="storage_configuration_error",
                fallback_allowed=False,
            ), 500
        else:
            upload_url = f"{Config.BASE_URL}/api/mobile/v2/uploads/mock-put/{upload_id}"

        return jsonify(
            ok=True,
            upload_id=upload_id,
            upload_url=upload_url,
            object_key=object_key,
            expires_at=expires_at.isoformat() + "Z",
            required_headers={"Content-Type": mime_type},
        )

    @bp.route("/api/mobile/v2/uploads/mock-put/<upload_id>", methods=["PUT"])
    @csrf.exempt
    def mobile_v2_mock_put(upload_id):
        # PRODUCTION GUARD: mock-PUT is a dev/CI convenience only.
        # Disabled whenever the server runs under HTTPS or when the explicit
        # opt-in env var ENABLE_MOCK_PUT is not set to "1".
        from config import Config  # avoid circular at module level

        if Config._PRODUCTION or os.environ.get("ENABLE_MOCK_PUT", "0") != "1":
            return jsonify(error="not_found"), 404
        session_row = fetch_one("SELECT * FROM upload_sessions WHERE upload_id=%s", (upload_id,))
        if not session_row:
            return jsonify(error="session_not_found"), 404
        mock_dir = Path("uploads/mock_quarantine") / str(session_row["child_id"]) / upload_id
        mock_dir.mkdir(parents=True, exist_ok=True)
        dest = mock_dir / f"source.{session_row['extension']}"
        chunk_size = 64 * 1024
        with dest.open("wb") as f:
            while True:
                chunk = request.stream.read(chunk_size)
                if not chunk:
                    break
                f.write(chunk)
        return "", 200

    @bp.route("/api/mobile/v2/uploads/<upload_id>/complete", methods=["POST"])
    @csrf.exempt
    @limiter.limit("30 per hour")
    @_require_mobile("CHILD")
    def mobile_v2_upload_complete(upload_id):
        uid = int(g.mobile_user["user_id"])
        session_row = fetch_one("SELECT * FROM upload_sessions WHERE upload_id=%s", (upload_id,))
        if not session_row:
            return jsonify(error="upload_session_not_found"), 404

        if int(session_row["child_id"]) != uid:
            return jsonify(error="forbidden_upload_owner_mismatch"), 403

        if session_row["status"] == "CONSUMED":
            existing = fetch_one(
                "SELECT post_id, processing_status, moderation_status FROM posts WHERE source_media_path=%s LIMIT 1",
                (session_row["object_key"],),
            )
            if existing:
                return jsonify(
                    ok=True,
                    post_id=existing["post_id"],
                    status=existing["processing_status"],
                    idempotent=True,
                )

        if session_row["expires_at"] and session_row["expires_at"] < datetime.utcnow():
            execute("UPDATE upload_sessions SET status='EXPIRED' WHERE upload_id=%s", (upload_id,))
            return jsonify(error="upload_session_expired"), 400

        from services import object_storage

        if object_storage.enabled():
            meta = object_storage.head_object(session_row["object_key"])
            if not meta or meta.get("content_length", 0) <= 0:
                return jsonify(error="media_object_missing_in_quarantine"), 400

        data = request.get_json(silent=True) or request.form or {}
        caption = str(data.get("caption") or "").strip()
        category = str(data.get("content_category") or "Other")
        category = category if category in SAFE_CATEGORIES else "Other"
        if category not in effective_categories(uid):
            return jsonify(error="category_disabled_by_parent"), 403

        audience_raw = data.get("audience_age_group")
        if audience_raw is not None and str(audience_raw) not in {"ALL", "6-8", "9-11", "12-13", "14-18"}:
            return jsonify(error="invalid_audience_age_group"), 400
        audience = str(audience_raw or "ALL")

        if caption and scan_pii(caption).get("detected"):
            parent_notify(uid, "CONTENT_BLOCKED", "Personal contact information cannot be shared in captions", "/parent/safety/")
            return jsonify(error="caption_pii_blocked"), 400

        raw_tags = data.get("tags") or []
        if isinstance(raw_tags, str):
            raw_tags = [t.strip() for t in raw_tags.split(",") if t.strip()]

        from services.tag_service import validate_and_normalize_tags, save_post_tags

        validated_tags, tag_err = validate_and_normalize_tags(raw_tags, uid)
        if tag_err:
            return jsonify(error=tag_err), 400

        kind = session_row["kind"].upper()
        media_type = session_row["media_type"].upper()

        location_name = str(data.get("location_name") or "").strip()[:120] or None
        music_id = data.get("music_id")
        music_row = None
        if kind == "STORY" and music_id:
            try:
                music_row = fetch_one("SELECT * FROM curated_music WHERE music_id=%s AND is_active=TRUE", (int(music_id),))
            except Exception:
                music_row = None
        s_music_id = music_row["music_id"] if music_row else None
        s_music_title = music_row["title"] if music_row else None
        s_music_artist = music_row["artist"] if music_row else None
        s_music_url = music_row["audio_url"] if music_row else None
        s_music_start = int(data.get("music_start") or 0)
        s_music_dur = int(data.get("music_duration") or (music_row["duration_seconds"] if music_row else 30))

        post_row = execute(
            """INSERT INTO posts(child_id, media_type, source_media_path, caption, content_category,
                               audience_age_group, is_story, is_reel, is_safe, moderation_status,
                               processing_status, processing_started_at, location_name,
                               story_music_id, story_music_title, story_music_artist, story_music_url, story_music_start, story_music_duration)
               VALUES(%s, %s, %s, %s, %s, %s, %s, %s, FALSE, 'PENDING', 'UPLOADED', NOW(), %s, %s, %s, %s, %s, %s, %s)
               RETURNING post_id""",
            (
                uid,
                media_type,
                session_row["object_key"],
                caption,
                category,
                audience,
                kind == "STORY",
                kind == "REEL",
                location_name,
                s_music_id,
                s_music_title,
                s_music_artist,
                s_music_url,
                s_music_start,
                s_music_dur,
            ),
            returning=True,
        )
        post_id = post_row["post_id"]

        if validated_tags:
            save_post_tags(post_id, validated_tags)

        execute(
            "UPDATE upload_sessions SET status='CONSUMED', consumed_at=NOW() WHERE upload_id=%s",
            (upload_id,),
        )

        from services.job_queue import enqueue_media_job

        enqueue_media_job(post_id, uid, session_row["object_key"], kind)

        return jsonify(
            ok=True,
            post_id=post_id,
            status="PROCESSING",
        )

    @bp.route("/api/mobile/v2/posts/<int:post_id>/processing-status", methods=["GET"])
    @_require_mobile("CHILD", "PARENT")
    def mobile_v2_processing_status(post_id):
        uid = int(g.mobile_user["user_id"])
        role = str(g.mobile_user["role"]).upper()

        post = fetch_one(
            """SELECT post_id, child_id, processing_status, moderation_status, is_safe,
                      media_path, poster_path, processing_error
               FROM posts WHERE post_id=%s""",
            (post_id,),
        )
        if not post:
            return jsonify(error="post_not_found"), 404

        owner_id = int(post["child_id"])
        if role == "CHILD" and owner_id != uid:
            return jsonify(error="forbidden_not_post_owner"), 403
        elif role == "PARENT" and not owns(uid, owner_id):
            return jsonify(error="forbidden_not_child_guardian"), 403

        st = post.get("processing_status") or "UPLOADED"
        return jsonify(
            ok=True,
            post_id=post_id,
            status=st,
            stage=st,
            moderation_status=post.get("moderation_status"),
            is_safe=bool(post.get("is_safe")),
            media_url=_asset_url(post.get("media_path")),
            poster_url=_asset_url(post.get("poster_path")),
            error=post.get("processing_error"),
        )


    @bp.route("/api/mobile/v1/kids/learning")
    @_require_mobile("CHILD")
    def mobile_learning():
        uid = int(g.mobile_user["user_id"])
        return jsonify(ok=True, points=learning_points(uid), challenges=_clean(learning_challenges(uid)))

    @bp.route("/api/mobile/v1/kids/learning/<int:challenge_id>", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_learning_answer(challenge_id):
        uid = int(g.mobile_user["user_id"])
        challenge = fetch_one("SELECT * FROM learning_challenges WHERE challenge_id=%s AND active=TRUE", (challenge_id,))
        if not challenge:
            return jsonify(error="challenge_not_found"), 404
        allowed = {x["challenge_id"] for x in learning_challenges(uid)}
        if challenge_id not in allowed:
            return jsonify(error="challenge_not_available"), 403
        response = str((request.get_json(silent=True) or {}).get("response") or "").strip()
        expected = str(challenge.get("expected_answer") or "").strip()
        correct = True if not expected else response.casefold() == expected.casefold()
        points = int(challenge.get("points") or 0) if correct else 0
        execute(
            """INSERT INTO learning_challenge_attempts(child_id,challenge_id,response,completed,points_awarded)
               VALUES(%s,%s,%s,%s,%s)
               ON CONFLICT(child_id,challenge_id) DO UPDATE SET response=EXCLUDED.response,completed=EXCLUDED.completed,
               points_awarded=EXCLUDED.points_awarded,completed_at=NOW()""",
            (uid, challenge_id, response, correct, points),
        )
        return jsonify(ok=True, correct=correct, points_awarded=points, total_points=learning_points(uid))

    @bp.route("/api/mobile/v1/kids/quiz")
    @_require_mobile("CHILD")
    def mobile_quiz():
        uid = int(g.mobile_user["user_id"])
        state = feed_quiz_state(uid)
        if state.get("required"):
            row = required_feed_quiz(uid)
            rows = [row] if row else []
            reason = "feed_break"
        else:
            limit_arg = request.args.get("limit", type=int)
            default_limit = 2 if needs_onboarding_quiz(uid) else 5
            n = limit_arg if (limit_arg and 1 <= limit_arg <= 20) else default_limit
            rows = quizzes(uid, n)
            reason = "onboarding" if needs_onboarding_quiz(uid) else "practice"

        if not rows:
            return jsonify(error="quiz_bank_unavailable"), 503

        payload = []
        for row in rows:
            if not row:
                continue
            payload.append({
                "quiz_id": row["quiz_id"],
                "category": row.get("category", "Safety"),
                "question": row["question"],
                "options": [row["option_a"], row["option_b"], row["option_c"], row["option_d"]],
            })
        return jsonify(
            ok=True,
            reason=reason,
            required=bool((state.get("required") or needs_onboarding_quiz(uid)) and len(payload) > 0),
            quizzes=_clean(payload),
        )

    @bp.route("/api/mobile/v1/kids/quiz/<int:quiz_id>/answer", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_quiz_answer(quiz_id):
        uid = int(g.mobile_user["user_id"])
        answer = str((request.get_json(silent=True) or {}).get("answer") or "").strip()
        if not answer:
            return jsonify(error="answer_required"), 400

        row = fetch_one(
            "SELECT * FROM quizzes WHERE quiz_id=%s AND age_group=%s",
            (quiz_id, age_group(uid)),
        )
        if not row:
            return jsonify(error="quiz_not_available"), 404
        correct, correct_answer, xp, explanation = record_feed_answer(uid, quiz_id, answer)
        state = feed_quiz_state(uid)
        if state.get("required") and state.get("quiz_id") == quiz_id:
            complete_required_feed_quiz(uid, quiz_id)
        return jsonify(
            ok=True,
            correct=correct,
            correct_answer=correct_answer,
            xp=xp,
            explanation=explanation,
            onboarding_complete=not needs_onboarding_quiz(uid),
            required=bool(feed_quiz_state(uid).get("required")),
        )

    @bp.route("/api/mobile/v1/kids/feed-view/<int:post_id>", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_feed_view(post_id):
        uid = int(g.mobile_user["user_id"])
        if not post_visible_to(uid, post_id):
            return jsonify(error="post_not_found"), 404
        state = record_feed_view(uid, post_id)
        return jsonify(ok=True, **_clean(state))

    @bp.route("/api/mobile/v1/kids/settings")
    @_require_mobile("CHILD")
    def mobile_kids_settings():
        uid = int(g.mobile_user["user_id"])
        limit_row = fetch_one("SELECT daily_limit_minutes FROM child_time_limits WHERE child_id=%s", (uid,))
        daily_limit = int(limit_row["daily_limit_minutes"]) if limit_row else 60
        safety_row = fetch_one("SELECT safety_level FROM parent_safety_settings WHERE child_id=%s", (uid,))
        s_level = safety_row["safety_level"] if safety_row else "STRICT"
        return jsonify(
            ok=True,
            profile=_profile_json(get_child_profile(uid)),
            controls=_clean(controls_for_child(uid)),
            minutes_today=minutes_today(uid),
            daily_limit=daily_limit,
            has_face=bool(fetch_one("SELECT 1 FROM face_profiles WHERE child_id=%s", (uid,))),
            safety_level=s_level,
        )

    @bp.route("/api/mobile/v1/kids/blocked-users")
    @_require_mobile("CHILD")
    def mobile_kids_blocked_users():
        uid = int(g.mobile_user["user_id"])
        rows = fetch_all(
            """SELECT u.user_id, u.username, u.full_name, cp.profile_picture, b.created_at
               FROM blocked_users b
               JOIN users u ON u.user_id = b.blocked_id
               LEFT JOIN child_profiles cp ON cp.child_id = u.user_id
               WHERE b.blocker_id = %s
               ORDER BY b.created_at DESC""",
            (uid,),
        )
        out = []
        for r in rows:
            item = dict(r)
            item["avatar_url"] = _asset_url(item.pop("profile_picture", None))
            out.append(_clean(item))
        return jsonify(ok=True, blocked_users=out)

    @bp.route("/api/mobile/v1/kids/block/<int:target_id>", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_kids_block(target_id):
        uid = int(g.mobile_user["user_id"])
        if target_id == uid:
            return jsonify(error="cannot_block_self"), 400
        data = request.get_json(silent=True) or {}
        action = str(data.get("action") or "block").lower()
        if action == "unblock":
            execute("DELETE FROM blocked_users WHERE blocker_id=%s AND blocked_id=%s", (uid, target_id))
            return jsonify(ok=True, blocked=False)
        execute("INSERT INTO blocked_users(blocker_id,blocked_id) VALUES(%s,%s) ON CONFLICT DO NOTHING", (uid, target_id))
        execute("DELETE FROM followers WHERE (child_id=%s AND following_child_id=%s) OR (child_id=%s AND following_child_id=%s)", (uid, target_id, target_id, uid))
        return jsonify(ok=True, blocked=True)

    @bp.route("/api/mobile/v1/kids/muted-users")
    @_require_mobile("CHILD")
    def mobile_kids_muted_users():
        uid = int(g.mobile_user["user_id"])
        rows = fetch_all(
            """SELECT u.user_id, u.username, u.full_name, cp.profile_picture, m.created_at
               FROM muted_users m
               JOIN users u ON u.user_id = m.muted_id
               LEFT JOIN child_profiles cp ON cp.child_id = u.user_id
               WHERE m.muter_id = %s
               ORDER BY m.created_at DESC""",
            (uid,),
        )
        out = []
        for r in rows:
            item = dict(r)
            item["avatar_url"] = _asset_url(item.pop("profile_picture", None))
            out.append(_clean(item))
        return jsonify(ok=True, muted_users=out)

    @bp.route("/api/mobile/v1/kids/mute/<int:target_id>", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_kids_mute(target_id):
        uid = int(g.mobile_user["user_id"])
        if target_id == uid:
            return jsonify(error="cannot_mute_self"), 400
        data = request.get_json(silent=True) or {}
        action = str(data.get("action") or "mute").lower()
        if action == "unmute":
            execute("DELETE FROM muted_users WHERE muter_id=%s AND muted_id=%s", (uid, target_id))
            return jsonify(ok=True, muted=False)
        execute("INSERT INTO muted_users(muter_id,muted_id) VALUES(%s,%s) ON CONFLICT DO NOTHING", (uid, target_id))
        return jsonify(ok=True, muted=True)

    @bp.route("/api/mobile/v1/kids/report", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_kids_report():
        uid = int(g.mobile_user["user_id"])
        data = request.get_json(silent=True) or {}
        kind = str(data.get("target_type") or "").upper()
        try:
            tid = int(data.get("target_id", 0))
        except (TypeError, ValueError):
            return jsonify(error="invalid_target"), 400
        reason = str(data.get("reason") or "").strip()
        details = str(data.get("details") or "").strip()
        if kind not in {"USER", "POST", "COMMENT", "MESSAGE"} or not reason or not tid:
            return jsonify(error="invalid_report"), 400

        valid = False
        if kind == "USER":
            is_child = bool(fetch_one("SELECT 1 FROM users WHERE user_id=%s AND role='CHILD' AND user_id<>%s", (tid, uid)))
            has_interaction = bool(fetch_one("SELECT 1 FROM followers WHERE (child_id=%s AND following_child_id=%s) OR (child_id=%s AND following_child_id=%s)", (uid, tid, tid, uid)))
            has_conv = bool(fetch_one("SELECT 1 FROM child_conversations WHERE (child1_id=%s AND child2_id=%s) OR (child1_id=%s AND child2_id=%s)", (min(uid, tid), max(uid, tid), min(uid, tid), max(uid, tid))))
            valid = is_child and (has_interaction or has_conv or can_discover_child(uid, tid))
        elif kind == "POST":
            from services.social import post_visible_to
            valid = bool(post_visible_to(uid, tid))
        elif kind == "COMMENT":
            from services.social import post_visible_to
            row = fetch_one("SELECT post_id FROM comments WHERE comment_id=%s AND moderation_status='ALLOWED'", (tid,))
            valid = bool(row and post_visible_to(uid, row["post_id"]))
        elif kind == "MESSAGE":
            valid = bool(fetch_one("SELECT 1 FROM child_messages WHERE child_message_id=%s AND (sender_child_id=%s OR receiver_child_id=%s)", (tid, uid, uid)))

        if not valid:
            return jsonify(error="target_unavailable"), 404

        execute(
            "INSERT INTO reports(reporter_id, target_type, target_id, reason, details) VALUES(%s, %s, %s, %s, %s)",
            (uid, kind, tid, reason[:100], details[:2000]),
        )
        parent_notify(uid, "REPORT_FILED", f"Report submitted for {kind.lower()}", "/parent/safety/")
        return jsonify(ok=True)

    @bp.route("/api/mobile/v1/parent/dashboard")
    @_require_mobile("PARENT")
    def mobile_parent_dashboard():
        pid = int(g.mobile_user["user_id"])
        kids = children(pid)
        for child in kids:
            cid = int(child["user_id"])
            child["minutes_today"] = minutes_today(cid)
            child["limit"] = fetch_one("SELECT * FROM child_time_limits WHERE child_id=%s", (cid,))
            child["safety"] = fetch_one("SELECT safety_level FROM parent_safety_settings WHERE child_id=%s", (cid,)) or {"safety_level": "STRICT"}
            child["open_reviews"] = (fetch_one("SELECT COUNT(*) n FROM moderation_events WHERE child_id=%s AND decision='REVIEW' AND status='OPEN'", (cid,)) or {"n": 0})["n"]
            child["controls"] = controls_for_child(cid)
            child["presence"] = online_state(cid)
            child["behavior"] = behavior_summary(cid)
            quiz = fetch_one("SELECT COUNT(*) attempted,COUNT(*) FILTER (WHERE is_correct) correct FROM child_quiz_attempts WHERE child_id=%s AND attempted_at>=NOW()-INTERVAL '7 days'", (cid,)) or {"attempted": 0, "correct": 0}
            attempted = int(quiz.get("attempted") or 0)
            correct = int(quiz.get("correct") or 0)
            child["quiz_7d"] = {"attempted": attempted, "correct": correct, "accuracy": round(correct * 100 / attempted) if attempted else 0}
            if child.get("profile_picture"):
                child["avatar_url"] = _asset_url(child.get("profile_picture"))
        unread = (fetch_one("SELECT COUNT(*) n FROM parent_notifications WHERE parent_id=%s AND is_read=FALSE", (pid,)) or {"n": 0})["n"]
        return jsonify(ok=True, children=_clean(kids), unread=unread, pending=_clean(pending_follows(pid)))

    @bp.route("/api/mobile/v1/parent/children", methods=["POST"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_create_child():
        data = request.get_json(silent=True) or {}
        try:
            child_id = create_child_for_verified_parent(int(g.mobile_user["user_id"]), data)
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        except Exception as exc:
            import logging
            logging.getLogger(__name__).exception("Failed to create child for parent %s: %s", g.mobile_user.get("user_id"), exc)
            err_msg = str(exc).lower()
            if "unique constraint" in err_msg or "duplicate key" in err_msg or "uniqueviolation" in err_msg:
                return jsonify(error="This username is already taken. Please choose another."), 400
            return jsonify(error="child_creation_failed", message=str(exc)), 400
        return jsonify(ok=True, child_id=child_id, next_steps=["child_face_enrollment", "age_quiz"]), 201

    @bp.route("/api/mobile/v1/parent/children/<int:child_id>/face/enroll", methods=["POST"])
    @csrf.exempt
    @limiter.limit("15 per minute")
    @_require_mobile("PARENT")
    def mobile_parent_enroll_child_face(child_id):
        pid = int(g.mobile_user["user_id"])
        if not owns(pid, child_id):
            return jsonify(error="child_not_found"), 404
        path = _save_request_image("littlenet_parent_enroll_child_")
        if not path:
            return jsonify(error="live_camera_photo_required"), 400
        try:
            try:
                enroll(child_id, path)
            except Exception as exc:
                import logging
                logging.getLogger(__name__).warning("Face enroll embedding skipped: %s", exc)

            b_key = secrets.token_hex(32)
            execute(
                """INSERT INTO face_profiles(child_id, embedding, model_name, biometric_key)
                   VALUES(%s, '[]'::jsonb, 'LocalBiometricV1', %s)
                   ON CONFLICT (child_id) DO UPDATE SET biometric_key=COALESCE(face_profiles.biometric_key, EXCLUDED.biometric_key), updated_at=NOW()""",
                (child_id, b_key),
            )
            return jsonify(
                ok=True,
                child_id=child_id,
                face_enrolled=True,
                biometric_key=b_key,
                quiz_required=bool(needs_onboarding_quiz(child_id)),
            )
        except Exception as exc:
            import logging
            logging.getLogger(__name__).exception("face_enrollment_failed: %s", exc)
            return jsonify(error="face_enrollment_failed", message=str(exc)), 400
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    @bp.route("/api/mobile/v1/parent/controls/<int:child_id>", methods=["GET", "PUT"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_controls(child_id):
        pid = int(g.mobile_user["user_id"])
        if not owns(pid, child_id):
            return jsonify(error="child_not_found"), 404
        if request.method == "PUT":
            data = request.get_json(silent=True) or {}
            current = controls_for_child(child_id)
            merged = dict(current)
            merged.update({k: data[k] for k in data if k in {
                "allow_reels", "allow_stories", "allow_messaging", "allow_posting", "allow_discover",
                "quiet_hours_enabled", "quiet_start", "quiet_end", "educational_only_feed", "allowed_categories",
            }})
            form = MultiDict()
            for flag in ("allow_reels", "allow_stories", "allow_messaging", "allow_posting", "allow_discover", "quiet_hours_enabled", "educational_only_feed"):
                if bool(merged.get(flag)):
                    form.add(flag, "on")
            form.add("quiet_start", str(merged.get("quiet_start") or "21:00"))
            form.add("quiet_end", str(merged.get("quiet_end") or "07:00"))
            for category in merged.get("allowed_categories") or SAFE_CATEGORIES:
                form.add("allowed_categories", category)
            try:
                save_controls(pid, child_id, form)
            except ValueError:
                return jsonify(error="invalid_quiet_hours"), 400
        limit_row = fetch_one("SELECT * FROM child_time_limits WHERE child_id=%s", (child_id,))
        return jsonify(
            ok=True,
            controls=_clean(controls_for_child(child_id)),
            time_limit=_clean(limit_row) if limit_row else None,
            categories=SAFE_CATEGORIES,
        )

    @bp.route("/api/mobile/v1/parent/child/<int:child_id>", methods=["DELETE"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_unlink_child(child_id):
        pid = int(g.mobile_user["user_id"])
        if not owns(pid, child_id):
            return jsonify(error="child_not_found"), 404
        execute("DELETE FROM parent_child_map WHERE child_id=%s AND (parent_id=%s OR verified_parent_id=%s)", (child_id, pid, pid))
        execute("UPDATE users SET account_status='DEACTIVATED' WHERE user_id=%s AND role='CHILD'", (child_id,))
        return jsonify(ok=True, message="child_unlinked")

    @bp.route("/api/mobile/v1/parent/child/<int:child_id>/reset-password", methods=["POST"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_reset_child_password(child_id):
        pid = int(g.mobile_user["user_id"])
        data = request.get_json(silent=True) or {}
        new_password = str(data.get("new_password") or "")
        ok, msg = parent_reset_child_password(pid, child_id, new_password)
        if not ok:
            return jsonify(ok=False, error=msg), 400
        return jsonify(ok=True, message=msg)


    @bp.route("/api/mobile/v1/parent/time-limit/<int:child_id>", methods=["PUT"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_time_limit(child_id):
        pid = int(g.mobile_user["user_id"])
        if not owns(pid, child_id):
            return jsonify(error="child_not_found"), 404
        data = request.get_json(silent=True) or {}
        try:
            minutes = int(data.get("daily_limit_minutes"))
        except (TypeError, ValueError):
            return jsonify(error="invalid_limit"), 400
        if not 1 <= minutes <= 1440:
            return jsonify(error="invalid_limit"), 400
        strict = bool(data.get("strict_mode", True))
        execute("INSERT INTO child_time_limits(child_id,daily_limit_minutes,strict_mode) VALUES(%s,%s,%s) ON CONFLICT(child_id) DO UPDATE SET daily_limit_minutes=EXCLUDED.daily_limit_minutes,strict_mode=EXCLUDED.strict_mode,updated_at=NOW()", (child_id, minutes, strict))
        return jsonify(ok=True, limit=_clean(fetch_one("SELECT * FROM child_time_limits WHERE child_id=%s", (child_id,))))

    @bp.route("/api/mobile/v1/parent/safety")
    @_require_mobile("PARENT")
    def mobile_parent_safety():
        pid = int(g.mobile_user["user_id"])
        rows = fetch_all("SELECT e.*,u.full_name FROM moderation_events e JOIN users u ON u.user_id=e.child_id WHERE e.decision='REVIEW' AND e.status='OPEN' AND e.child_id IN (SELECT child_id FROM parent_child_map WHERE parent_id=%s) ORDER BY e.created_at DESC", (pid,))
        out = []
        for event in rows:
            item = dict(event)
            preview = None
            if item.get("content_type") in {"IMAGE", "VIDEO", "TEXT"} and item.get("content_id"):
                preview = fetch_one("SELECT media_type,media_path,caption FROM posts WHERE post_id=%s", (item["content_id"],))
            elif item.get("content_type") == "COMMENT" and item.get("content_id"):
                preview = fetch_one("SELECT comment_text FROM comments WHERE comment_id=%s", (item["content_id"],))
            elif item.get("content_type") == "MESSAGE" and item.get("content_id"):
                preview = fetch_one("SELECT message_type,message_text,media_path,shared_post_id FROM child_messages WHERE child_message_id=%s", (item["content_id"],))
            if preview:
                preview = dict(preview)
                if preview.get("media_path"):
                    preview["media_url"] = _asset_url(preview.pop("media_path"))
            item["preview"] = _clean(preview)
            out.append(_clean(item))
        return jsonify(ok=True, events=out)

    @bp.route("/api/mobile/v1/parent/safety/<int:event_id>", methods=["POST"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_review(event_id):
        action = str((request.get_json(silent=True) or {}).get("action") or "").upper()
        ok, result = _resolve_parent_review(int(g.mobile_user["user_id"]), event_id, action)
        return jsonify(ok=ok, result=result), (200 if ok else 400)

    @bp.route("/api/mobile/v1/parent/follow-requests")
    @_require_mobile("PARENT")
    def mobile_parent_follow_requests():
        return jsonify(ok=True, pending=_clean(pending_follows(int(g.mobile_user["user_id"]))))

    @bp.route("/api/mobile/v1/parent/follow-requests/action", methods=["POST"])
    @csrf.exempt
    @_require_mobile("PARENT")
    def mobile_parent_follow_action():
        data = request.get_json(silent=True) or {}
        try:
            child_id = int(data.get("child_id"))
            target_id = int(data.get("target_id"))
        except (TypeError, ValueError):
            return jsonify(error="invalid_ids"), 400
        if not owns(int(g.mobile_user["user_id"]), child_id):
            return jsonify(error="forbidden"), 403
        action = str(data.get("action") or "").lower()
        if action == "approve":
            execute("UPDATE followers SET approved=TRUE,approval_stage='ACTIVE' WHERE child_id=%s AND following_child_id=%s AND approved=FALSE", (child_id, target_id))
        elif action == "reject":
            execute("DELETE FROM followers WHERE child_id=%s AND following_child_id=%s AND approved=FALSE", (child_id, target_id))
        else:
            return jsonify(error="invalid_action"), 400
        return jsonify(ok=True, action=action)

    @bp.route("/api/mobile/v1/parent/notifications")
    @_require_mobile("PARENT")
    def mobile_parent_notifications():
        pid = int(g.mobile_user["user_id"])
        rows = fetch_all("SELECT * FROM parent_notifications WHERE parent_id=%s ORDER BY created_at DESC LIMIT 100", (pid,))
        return jsonify(ok=True, notifications=_clean(rows))

    @bp.route("/api/mobile/v1/admin/dashboard")
    @_require_mobile("ADMIN")
    def mobile_admin_dashboard():
        counts_row = {
            "users": (fetch_one("SELECT COUNT(*) n FROM users", ()) or {"n": 0})["n"],
            "children": (fetch_one("SELECT COUNT(*) n FROM users WHERE role='CHILD'", ()) or {"n": 0})["n"],
            "parents": (fetch_one("SELECT COUNT(*) n FROM users WHERE role='PARENT'", ()) or {"n": 0})["n"],
            "open_reviews": (fetch_one("SELECT COUNT(*) n FROM moderation_events WHERE decision='REVIEW' AND status='OPEN'", ()) or {"n": 0})["n"],
        }
        return jsonify(ok=True, counts=_clean(counts_row))

    @bp.route("/api/mobile/v1/admin/reviews")
    @_require_mobile("ADMIN")
    def mobile_admin_reviews():
        rows = fetch_all("SELECT e.*,u.full_name,u.username FROM moderation_events e JOIN users u ON u.user_id=e.child_id WHERE e.status='OPEN' ORDER BY e.created_at DESC LIMIT 100")
        return jsonify(ok=True, events=_clean(rows))

    @bp.route("/api/mobile/v2/kids/feed")
    @_require_mobile("CHILD")
    def mobile_kids_feed_v2():
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        try:
            cursor = max(0, int(request.args.get("cursor", 0)))
        except (TypeError, ValueError):
            cursor = 0
        try:
            limit = min(50, max(1, int(request.args.get("limit", 10))))
        except (TypeError, ValueError):
            limit = 10
        session_id = request.args.get("session_id")
        page = get_feed_page(uid, surface="FEED", cursor=cursor, limit=limit, session_id=session_id)
        from services.media_delivery import resolve_media_delivery
        for item in page["items"]:
            if item.get("media_reference"):
                m_res = resolve_media_delivery(item["media_reference"], viewer_id=uid, viewer_role="CHILD")
                item["media_url"] = m_res.get("url")
                if m_res.get("expires_at"):
                    item["playback_expires_at"] = m_res["expires_at"]
            if item.get("poster_reference"):
                p_res = resolve_media_delivery(item["poster_reference"], viewer_id=uid, viewer_role="CHILD")
                item["poster_url"] = p_res.get("url")
        return jsonify(ok=True, **_clean(page))

    @bp.route("/api/mobile/v2/kids/reels")
    @_require_mobile("CHILD")
    def mobile_kids_reels_v2():
        gate = _child_gate("reels")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        try:
            cursor = max(0, int(request.args.get("cursor", 0)))
        except (TypeError, ValueError):
            cursor = 0
        try:
            limit = min(50, max(1, int(request.args.get("limit", 10))))
        except (TypeError, ValueError):
            limit = 10
        session_id = request.args.get("session_id")
        page = get_feed_page(uid, surface="REELS", cursor=cursor, limit=limit, session_id=session_id)
        from services.media_delivery import resolve_media_delivery
        for item in page["items"]:
            if item.get("media_reference"):
                m_res = resolve_media_delivery(item["media_reference"], viewer_id=uid, viewer_role="CHILD")
                item["media_url"] = m_res.get("url")
                if m_res.get("expires_at"):
                    item["playback_expires_at"] = m_res["expires_at"]
            if item.get("poster_reference"):
                p_res = resolve_media_delivery(item["poster_reference"], viewer_id=uid, viewer_role="CHILD")
                item["poster_url"] = p_res.get("url")
        return jsonify(ok=True, **_clean(page))

    @bp.route("/api/mobile/v2/curated/media/<int:content_id>")
    @_require_mobile("CHILD")
    def mobile_curated_media(content_id):
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        try:
            payload = authorize_curated_media(uid, content_id)
            return jsonify(ok=True, **_clean(payload))
        except FileNotFoundError:
            return jsonify(error="content_not_found"), 404
        except PermissionError as exc:
            return jsonify(error=str(exc)), 403

    @bp.route("/api/mobile/v2/kids/impressions", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_record_impression():
        gate = _child_gate()
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        data = request.get_json(silent=True) or {}
        session_id = str(data.get("session_id") or "").strip()
        source_type = str(data.get("source_type") or "POST").strip().upper()
        try:
            source_id = int(data.get("source_id"))
        except (TypeError, ValueError):
            return jsonify(error="invalid_source_id"), 400
        surface = str(data.get("surface") or "FEED").strip().upper()
        watched_ms = data.get("watched_ms")
        if watched_ms is not None:
            try:
                watched_ms = max(0, int(watched_ms))
            except (TypeError, ValueError):
                watched_ms = None
        completed = bool(data.get("completed", False))
        liked = bool(data.get("liked", False))
        saved = bool(data.get("saved", False))

        state = feed_quiz_state(uid)
        if state.get("required"):
            return jsonify(error="quiz_required", gate="quiz", quiz_required=True), 428

        ok = record_feed_impression(
            uid, session_id, source_type, source_id, surface,
            watched_ms=watched_ms, completed=completed, liked=liked, saved=saved
        )
        if not ok:
            return jsonify(error="invalid_session_item"), 403

        # Advance combined server counter for eligible substantially-viewed item
        view_res = record_feed_view(uid, source_id, source_type=source_type)
        if view_res.get("required"):
            return jsonify(
                ok=True,
                quiz_required=True,
                gate="quiz",
                posts_seen=view_res.get("posts_seen", 4),
                error="quiz_required",
            ), 428

        return jsonify(
            ok=True,
            quiz_required=False,
            posts_seen=view_res.get("posts_seen", 0),
        )

    @bp.route("/api/mobile/v2/kids/discover")
    @_require_mobile("CHILD")
    def mobile_kids_discover_v2():
        gate = _child_gate("discover")
        if gate:
            return gate
        uid = int(g.mobile_user["user_id"])
        q = str(request.args.get("q") or "").strip()
        if q and scan_pii(q).get("detected"):
            return jsonify(ok=True, pii_warning=True, children=[], posts=[], curated=[])

        kids = discoverable_children(uid, q.lstrip("#") if q and not q.startswith("#") else None, 30)
        out_kids = []
        for child in kids:
            row = dict(child)
            row["avatar_url"] = _asset_url(row.get("profile_picture"))
            row["is_following"] = is_following(uid, row["user_id"])
            row["is_pending"] = is_follow_pending(uid, row["user_id"])
            row.pop("profile_picture", None)
            out_kids.append(_clean(row))

        posts = discoverable_posts(uid, False, 30, 0)
        if q:
            needle = q.lstrip("#").casefold()
            posts = [
                p for p in posts
                if needle in str(p.get("caption") or "").casefold()
                or needle in str(p.get("content_category") or "").casefold()
                or needle in str(p.get("full_name") or "").casefold()
            ]

        curated = search_curated_content(uid, q, limit=20) if q else []
        for item in curated:
            if item.get("media_reference"):
                item["media_url"] = _asset_url(item["media_reference"])
            if item.get("poster_reference"):
                item["poster_url"] = _asset_url(item["poster_reference"])

        return jsonify(
            ok=True,
            pii_warning=False,
            children=out_kids,
            posts=[_post_json(p, uid) for p in posts],
            curated=_clean(curated),
        )
