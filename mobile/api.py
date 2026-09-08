from __future__ import annotations

import base64
import os
import tempfile
import uuid
from datetime import date, datetime
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
from services.social import (
    active_stories,
    can_interact,
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


def _asset_url(reference):
    if not reference:
        return None
    ref = str(reference)
    if ref.startswith(("http://", "https://")):
        return ref
    if ref.startswith("static/"):
        return f"{Config.BASE_URL.rstrip('/')}/{ref.lstrip('/')}"
    return f"{Config.BASE_URL.rstrip('/')}/api/mobile/v1/media?ref={quote(ref, safe='')}"


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
    out["media_url"] = _asset_url(out.get("media_path"))
    out["avatar_url"] = _asset_url(out.get("profile_picture"))
    out.pop("media_path", None)
    out.pop("profile_picture", None)
    out.pop("story_music_path", None)
    if viewer_id and out.get("post_id"):
        pid = int(out["post_id"])
        out["viewer_liked"] = bool(fetch_one("SELECT 1 FROM likes WHERE post_id=%s AND child_id=%s", (pid, viewer_id)))
        out["viewer_saved"] = bool(fetch_one("SELECT 1 FROM saved_posts WHERE post_id=%s AND child_id=%s", (pid, viewer_id)))
    return _clean(out)


def _save_request_image(prefix: str):
    upload = request.files.get("photo") or request.files.get("media")
    if upload and upload.filename:
        suffix = os.path.splitext(upload.filename)[1].lower() or ".jpg"
        fd, path = tempfile.mkstemp(prefix=prefix, suffix=suffix)
        os.close(fd)
        upload.save(path)
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
    if user.get("role") == "CHILD":
        profile = _profile_json(get_child_profile(user["user_id"]))
    return {
        "user_id": int(user["user_id"]),
        "username": user.get("username"),
        "full_name": user.get("full_name"),
        "email": user.get("email"),
        "role": user.get("role"),
        "age": user.get("age"),
        "profile": profile,
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
    if user["role"] == "CHILD":
        uid = int(user["user_id"])
        response["onboarding"] = {
            "face_required": not bool(fetch_one("SELECT 1 FROM face_profiles WHERE child_id=%s", (uid,))),
            "quiz_required": bool(needs_onboarding_quiz(uid)),
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
        return jsonify(ok=True, client="flutter", webview=False, api_version=1)

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
            result = verify_adult_face(path)
            if not result.get("is_adult"):
                return jsonify(error="adult_liveness_failed", reason=result.get("reason")), 403
            enroll(int(pending["uid"]), path)
            execute("UPDATE users SET account_status='ACTIVE' WHERE user_id=%s AND role='PARENT'", (int(pending["uid"]),))
            user = fetch_one("SELECT * FROM users WHERE user_id=%s", (int(pending["uid"]),))
            return _mobile_login_response(user, "PARENT_LIVENESS")
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
            enroll(g.mobile_user["user_id"], path)
            return jsonify(ok=True, quiz_required=bool(needs_onboarding_quiz(g.mobile_user["user_id"])))
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
            execute("UPDATE child_messages SET is_seen=TRUE,seen_at=NOW(),delivered_at=COALESCE(delivered_at,NOW()) WHERE conversation_id=%s AND receiver_child_id=%s AND moderation_status='ALLOWED'", (cid, uid))
            peer = fetch_one("SELECT user_id,username,full_name FROM users WHERE user_id=%s", (peer_id,)) or {}
            rows = messages(cid, uid)
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

    @bp.route("/api/mobile/v1/kids/posts/<int:post_id>/comment", methods=["POST"])
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
            return jsonify(blocked=True, error="comment_blocked"), 400
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
        audience = str(request.form.get("audience_age_group") or "ALL")
        if audience not in {"ALL", "6-8", "9-11", "12-13", "14-18"}:
            audience = "ALL"
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
            row = execute(
                """INSERT INTO posts(child_id,media_type,media_path,caption,content_category,audience_age_group,is_story,is_reel,
                   safety_score,adult_score,violence_score,weapon_score,toxicity_score,is_safe,moderation_status,moderation_reason)
                   VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING post_id""",
                (
                    uid, content_type, stored, caption, category, audience, kind == "story", kind == "reel",
                    decision.risk, merged["adult_score"] * 100, merged["violence_score"] * 100,
                    merged["weapon_score"] * 100, merged["toxicity_score"] * 100,
                    decision.action == "ALLOW", "ALLOWED" if decision.action == "ALLOW" else "REVIEW", decision.reason,
                ),
                returning=True,
            )
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
            rows = quizzes(uid, 2)
            reason = "onboarding" if needs_onboarding_quiz(uid) else "practice"
        payload = []
        for row in rows:
            if not row:
                continue
            payload.append({
                "quiz_id": row["quiz_id"],
                "category": row.get("category"),
                "question": row["question"],
                "options": [row["option_a"], row["option_b"], row["option_c"], row["option_d"]],
            })
        return jsonify(ok=True, reason=reason, required=bool(state.get("required") or needs_onboarding_quiz(uid)), quizzes=_clean(payload))

    @bp.route("/api/mobile/v1/kids/quiz/<int:quiz_id>/answer", methods=["POST"])
    @csrf.exempt
    @_require_mobile("CHILD")
    def mobile_quiz_answer(quiz_id):
        uid = int(g.mobile_user["user_id"])
        answer = str((request.get_json(silent=True) or {}).get("answer") or "").strip()
        if not answer:
            return jsonify(error="answer_required"), 400
        row = fetch_one("SELECT * FROM quizzes WHERE quiz_id=%s", (quiz_id,))
        if not row or row.get("age_group") != age_group(uid):
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
        except Exception:
            return jsonify(error="child_creation_failed"), 400
        return jsonify(ok=True, child_id=child_id, next_steps=["child_face_enrollment", "age_quiz"]), 201

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
        return jsonify(ok=True, controls=_clean(controls_for_child(child_id)), categories=SAFE_CATEGORIES)

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
