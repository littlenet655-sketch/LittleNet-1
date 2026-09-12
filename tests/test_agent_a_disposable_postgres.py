import os
import re
import json
import uuid
from pathlib import Path
from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
import pytest
import psycopg2
from psycopg2.extras import RealDictCursor

from app import app
from mobile.api import _issue_token, _resolve_parent_review
from safety import face_service
from services import media_processor
from services.job_queue import enqueue_media_job
from config import Config


def _get_disposable_url():
    p = Path(".env.disposable")
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if "DATABASE_URL" in line:
                return line.split("=", 1)[1].strip().strip('"\'')
    return os.getenv("DISPOSABLE_DATABASE_URL") or os.getenv("DATABASE_URL")


DISPOSABLE_URL = _get_disposable_url()
pytestmark = pytest.mark.skipif(not DISPOSABLE_URL, reason="Disposable PostgreSQL URL not configured")


@pytest.fixture(scope="session", autouse=True)
def configure_disposable_db():
    Config.DATABASE_URL = DISPOSABLE_URL
    import database.connection as db_conn
    # Reset thread pool
    with db_conn._pool_lock:
        if db_conn._pool and not db_conn._pool.closed:
            db_conn._pool.closeall()
        db_conn._pool = None


@pytest.fixture
def db():
    conn = psycopg2.connect(DISPOSABLE_URL, cursor_factory=RealDictCursor)
    conn.autocommit = True
    yield conn
    conn.close()


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def _random_user(db, role="CHILD"):
    suffix = uuid.uuid4().hex[:8]
    username = f"user_{suffix}"
    email = f"{username}@example.com"
    cur = db.cursor()
    cur.execute(
        """INSERT INTO users (username, full_name, email, password_hash, role, account_status)
           VALUES (%s, %s, %s, 'test_hash', %s, 'ACTIVE')
           RETURNING user_id, username, email, role, account_status""",
        (username, username, email, role),
    )
    user = cur.fetchone()
    if role == "CHILD":
        cur.execute(
            "INSERT INTO child_profiles (child_id, full_name, age) VALUES (%s, %s, 10)",
            (user["user_id"], username),
        )
    return user


def _auth_headers(user):
    token = _issue_token({"user_id": user["user_id"], "role": user["role"], "full_name": user["username"]})
    return {"Authorization": f"Bearer {token}"}


# ============================================================================
# 1. EXACT 512-DIM FACE VALIDATION & WRONG MODEL (DB LEVEL)
# ============================================================================

def test_db_face_profiles_constraint_exact_512_dimensions(db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    cur = db.cursor()

    # 1. 128 dimensions -> REJECTED by DB constraint
    with pytest.raises(psycopg2.IntegrityError):
        cur.execute(
            "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
            (uid, json.dumps([0.1] * 128)),
        )

    # 2. 511 dimensions -> REJECTED by DB constraint
    with pytest.raises(psycopg2.IntegrityError):
        cur.execute(
            "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
            (uid, json.dumps([0.1] * 511)),
        )

    # 3. 513 dimensions -> REJECTED by DB constraint
    with pytest.raises(psycopg2.IntegrityError):
        cur.execute(
            "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
            (uid, json.dumps([0.1] * 513)),
        )

    # 4. Wrong model_name -> REJECTED by DB constraint
    with pytest.raises(psycopg2.IntegrityError):
        cur.execute(
            "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'VGG-Face')",
            (uid, json.dumps([0.1] * 512)),
        )

    # 5. Exactly 512 dimensions with model_name='Facenet512' -> SUCCEEDS
    cur.execute(
        "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
        (uid, json.dumps([0.1] * 512)),
    )
    row = cur.execute("SELECT child_id, model_name, jsonb_array_length(embedding) as len FROM face_profiles WHERE child_id=%s", (uid,))
    row = cur.fetchone()
    assert row["child_id"] == uid
    assert row["model_name"] == "Facenet512"
    assert row["len"] == 512


# ============================================================================
# 2. FRESH FACE SUCCESS / MISMATCH / LIVENESS (SERVICE + REAL DB)
# ============================================================================

def test_real_db_face_verification_matrix(db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    cur = db.cursor()

    enrolled_vec = [0.05] * 512
    cur.execute(
        "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
        (uid, json.dumps(enrolled_vec)),
    )

    # 1. Matching capture -> SUCCESS (matched)
    with patch("safety.remote_client.enabled", return_value=False), \
         patch("safety.face_service._embedding", return_value=enrolled_vec):
        match, reason, dist = face_service.verify(uid, "selfie.jpg")
        assert match is True
        assert reason == "matched"
        assert dist is not None and dist < 0.35

    # Check attempt logged in face_login_attempts
    cur.execute("SELECT * FROM face_login_attempts WHERE child_id=%s ORDER BY attempt_id DESC LIMIT 1", (uid,))
    att = cur.fetchone()
    assert att["success"] is True

    # 2. Mismatch capture -> FAILS (not_matched)
    diff_vec = [-0.05] * 512
    with patch("safety.remote_client.enabled", return_value=False), \
         patch("safety.face_service._embedding", return_value=diff_vec):
        match, reason, dist = face_service.verify(uid, "selfie.jpg")
        assert match is False
        assert reason in ("not_matched", "face_mismatch")

    cur.execute("SELECT * FROM face_login_attempts WHERE child_id=%s ORDER BY attempt_id DESC LIMIT 1", (uid,))
    att = cur.fetchone()
    assert att["success"] is False
    assert att["reason"] in ("not_matched", "face_mismatch")

    # 3. Spoof / liveness failure -> FAILS (liveness_failed)
    with patch("safety.remote_client.enabled", return_value=False), \
         patch("safety.face_service._embedding", side_effect=ValueError("liveness_failed")):
        match, reason, dist = face_service.verify(uid, "selfie.jpg")
        assert match is False
        assert reason == "liveness_failed"

    cur.execute("SELECT * FROM face_login_attempts WHERE child_id=%s ORDER BY attempt_id DESC LIMIT 1", (uid,))
    att = cur.fetchone()
    assert att["success"] is False
    assert att["reason"] == "liveness_failed"


# ============================================================================
# 3. CONCURRENT /COMPLETE CALLS (EXACTLY ONE POST AND ONE LOGICAL JOB)
# ============================================================================

def test_concurrent_upload_complete_produces_exactly_one_post(client, db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    headers = _auth_headers(user)
    cur = db.cursor()

    # Enroll face for gate
    cur.execute(
        "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
        (uid, json.dumps([0.05] * 512)),
    )

    upload_id = str(uuid.uuid4())
    object_key = f"uploads/r2/quarantine/{uid}/{upload_id}.jpg"
    cur.execute(
        """INSERT INTO upload_sessions(upload_id, child_id, object_key, media_type, kind, expected_size_bytes, mime_type, extension, status, expires_at)
           VALUES(%s, %s, %s, 'IMAGE', 'POST', 1000, 'image/jpeg', 'jpg', 'UPLOADED', NOW() + INTERVAL '1 hour')""",
        (upload_id, uid, object_key),
    )

    dispatched_jobs = []

    def fake_enqueue(post_id, child_id, key, kind):
        job_id = f"modal_job_{uuid.uuid4().hex[:8]}"
        dispatched_jobs.append(job_id)
        return job_id

    with patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.head_object", return_value={"content_length": 1000, "content_type": "image/jpeg"}), \
         patch("services.job_queue.enqueue_media_job", side_effect=fake_enqueue):

        def call_complete():
            with app.test_client() as c:
                return c.post(f"/api/mobile/v2/uploads/{upload_id}/complete", headers=headers, json={"caption": "Two simultaneous calls"})

        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(call_complete)
            future2 = executor.submit(call_complete)
            res1 = future1.result()
            res2 = future2.result()

        assert res1.status_code == 200
        assert res2.status_code == 200
        data1 = res1.get_json()
        data2 = res2.get_json()

        assert data1["ok"] is True
        assert data2["ok"] is True
        # Both must return the identical post_id
        assert data1["post_id"] == data2["post_id"]
        post_id = data1["post_id"]

        # Exactly ONE post row in DB
        cur.execute("SELECT COUNT(*) as cnt FROM posts WHERE upload_id=%s", (upload_id,))
        assert cur.fetchone()["cnt"] == 1

        # Exactly ONE upload_session marked CONSUMED
        cur.execute("SELECT status FROM upload_sessions WHERE upload_id=%s", (upload_id,))
        assert cur.fetchone()["status"] == "CONSUMED"

        # Exactly ONE logical job dispatched
        assert len(dispatched_jobs) == 1


# ============================================================================
# 4. DISPATCH FAILURE + RETRYABILITY
# ============================================================================

def test_dispatch_failure_and_idempotent_retry(client, db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    headers = _auth_headers(user)
    cur = db.cursor()

    cur.execute(
        "INSERT INTO face_profiles(child_id, embedding, model_name) VALUES(%s, %s::jsonb, 'Facenet512')",
        (uid, json.dumps([0.05] * 512)),
    )

    upload_id = str(uuid.uuid4())
    object_key = f"uploads/r2/quarantine/{uid}/{upload_id}.jpg"
    cur.execute(
        """INSERT INTO upload_sessions(upload_id, child_id, object_key, media_type, kind, expected_size_bytes, mime_type, extension, status, expires_at)
           VALUES(%s, %s, %s, 'IMAGE', 'POST', 1000, 'image/jpeg', 'jpg', 'UPLOADED', NOW() + INTERVAL '1 hour')""",
        (upload_id, uid, object_key),
    )

    # 1. Initial attempt fails Modal spawn
    with patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.head_object", return_value={"content_length": 1000, "content_type": "image/jpeg"}), \
         patch("services.job_queue.enqueue_media_job", side_effect=RuntimeError("Modal capacity exhausted")):

        res = client.post(f"/api/mobile/v2/uploads/{upload_id}/complete", headers=headers, json={"caption": "Spawn failure test"})
        assert res.status_code == 503
        data = res.get_json()
        assert data["ok"] is False
        assert data["error"] == "job_dispatch_failed"
        assert data["retryable"] is True
        post_id = data["post_id"]

    # Verify DB post is UPLOADED with dispatch_failed error
    cur.execute("SELECT processing_status, processing_error FROM posts WHERE post_id=%s", (post_id,))
    p_row = cur.fetchone()
    assert p_row["processing_status"] == "UPLOADED"
    assert "dispatch_failed" in p_row["processing_error"]

    # 2. Retry succeeds
    with patch("services.object_storage.enabled", return_value=True), \
         patch("services.job_queue.enqueue_media_job", return_value="modal_retry_123"):

        retry_res = client.post(f"/api/mobile/v2/uploads/{upload_id}/complete", headers=headers, json={})
        assert retry_res.status_code == 200
        retry_data = retry_res.get_json()
        assert retry_data["ok"] is True
        assert retry_data["post_id"] == post_id
        assert retry_data["status"] == "PROCESSING"

    # Verify DB post is now PROCESSING
    cur.execute("SELECT processing_status, job_id, processing_error FROM posts WHERE post_id=%s", (post_id,))
    p_updated = cur.fetchone()
    assert p_updated["processing_status"] == "PROCESSING"
    assert p_updated["job_id"] == "modal_retry_123"
    assert p_updated["processing_error"] is None


# ============================================================================
# 5. BOUNDED REDRIVE & TERMINAL FAILURE
# ============================================================================

def test_bounded_redrive_terminates_at_max_attempts(db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    cur = db.cursor()
    src_key = f"uploads/r2/quarantine/{uuid.uuid4().hex}.jpg"

    cur.execute(
        """INSERT INTO posts(child_id, media_type, source_media_path, caption, processing_status, processing_attempts, max_processing_attempts, last_attempt_at)
           VALUES(%s, 'IMAGE', %s, 'Redrive test', 'PROCESSING', 2, 3, NOW() - INTERVAL '10 minutes')
           RETURNING post_id""",
        (uid, src_key),
    )
    post_id = cur.fetchone()["post_id"]

    # Attempt 3 (within limit) -> redrives
    with patch("services.job_queue.enqueue_media_job", return_value="job_attempt_3"):
        res = media_processor.redrive_media_job(post_id)
        assert res["ok"] is True
        assert res["attempts"] == 3

    # Attempt 4 (exceeds max_attempts of 3) -> terminates to FAILED
    res4 = media_processor.redrive_media_job(post_id)
    assert res4["ok"] is False
    assert res4["error"] == "max_attempts_exceeded"
    assert res4["status"] == "FAILED"

    cur.execute("SELECT processing_status, processing_error FROM posts WHERE post_id=%s", (post_id,))
    p = cur.fetchone()
    assert p["processing_status"] == "FAILED"
    assert p["processing_error"] == "max_attempts_exceeded"


def test_reap_stale_jobs_marks_exceeded_attempts_as_failed(db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    cur = db.cursor()
    src_key = f"uploads/r2/quarantine/{uuid.uuid4().hex}.jpg"

    cur.execute(
        """INSERT INTO posts(child_id, media_type, source_media_path, caption, processing_status,
                             processing_attempts, max_processing_attempts, created_at, processing_started_at)
           VALUES(%s, 'IMAGE', %s, 'Stale reaper test', 'PROCESSING',
                  3, 3, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour')
           RETURNING post_id""",
        (uid, src_key),
    )
    post_id = cur.fetchone()["post_id"]

    res = media_processor.reap_stale_media_jobs(stale_seconds=300)
    assert res["ok"] is True
    failed_ids = [f["post_id"] for f in res.get("failed", [])]
    assert post_id in failed_ids

    cur.execute("SELECT processing_status, processing_error FROM posts WHERE post_id=%s", (post_id,))
    p = cur.fetchone()
    assert p["processing_status"] == "FAILED"
    assert "max_attempts_exceeded" in p["processing_error"]


# ============================================================================
# 6. REVIEW LIFECYCLE: APPROVE & BLOCK ORDERING
# ============================================================================

def test_real_db_review_approval_lifecycle(db):
    parent = _random_user(db, "PARENT")
    child = _random_user(db, "CHILD")
    pid = parent["user_id"]
    cid = child["user_id"]
    cur = db.cursor()

    # Map parent to child
    cur.execute(
        """INSERT INTO parent_child_map(parent_id, child_id, parent_name, parent_email, approved, approval_status)
           VALUES(%s, %s, %s, %s, TRUE, 'APPROVED')""",
        (pid, cid, parent["username"], parent["email"]),
    )

    src_key = f"uploads/r2/quarantine/{uuid.uuid4().hex}.jpg"
    cur.execute(
        """INSERT INTO posts(child_id, media_type, source_media_path, caption, moderation_status, processing_status, is_safe)
           VALUES(%s, 'IMAGE', %s, 'Please approve', 'REVIEW', 'REVIEW', FALSE)
           RETURNING post_id""",
        (cid, src_key),
    )
    post_id = cur.fetchone()["post_id"]

    cur.execute(
        """INSERT INTO moderation_events(child_id, content_type, content_id, decision, status)
           VALUES(%s, 'IMAGE', %s, 'REVIEW', 'OPEN')
           RETURNING event_id""",
        (cid, post_id),
    )
    event_id = cur.fetchone()["event_id"]

    notifications_sent = []
    quarantine_cleaned = []

    def fake_notify(p_id, c_id, kind):
        notifications_sent.append(p_id)

    def fake_cleanup(p_id, key):
        quarantine_cleaned.append(key)
        return True

    with patch("services.media_processor.sanitize_and_promote_media", return_value=("uploads/r2/posts/clean.jpg", None)), \
         patch("services.media_processor._notify_approved_followers", side_effect=fake_notify), \
         patch("services.media_processor.block_and_cleanup_quarantine", side_effect=fake_cleanup):

        ok, result = _resolve_parent_review(pid, event_id, "APPROVE")
        assert ok is True
        assert result == "APPROVE"

    # Post must be ALLOWED in DB
    cur.execute("SELECT moderation_status, processing_status, is_safe, media_path FROM posts WHERE post_id=%s", (post_id,))
    post = cur.fetchone()
    assert post["moderation_status"] == "ALLOWED"
    assert post["processing_status"] == "ALLOWED"
    assert post["is_safe"] is True
    assert post["media_path"] == "uploads/r2/posts/clean.jpg"

    # Event resolved
    cur.execute("SELECT status FROM moderation_events WHERE event_id=%s", (event_id,))
    assert cur.fetchone()["status"] == "RESOLVED"

    # Review recorded
    cur.execute("SELECT action FROM moderation_reviews WHERE event_id=%s", (event_id,))
    assert cur.fetchone()["action"] == "APPROVE"

    # Post-commit hooks fired
    assert post_id in notifications_sent
    assert src_key in quarantine_cleaned


def test_real_db_review_block_lifecycle(db):
    parent = _random_user(db, "PARENT")
    child = _random_user(db, "CHILD")
    pid = parent["user_id"]
    cid = child["user_id"]
    cur = db.cursor()

    cur.execute(
        """INSERT INTO parent_child_map(parent_id, child_id, parent_name, parent_email, approved, approval_status)
           VALUES(%s, %s, %s, %s, TRUE, 'APPROVED')""",
        (pid, cid, parent["username"], parent["email"]),
    )

    src_key = f"uploads/r2/quarantine/{uuid.uuid4().hex}.jpg"
    cur.execute(
        """INSERT INTO posts(child_id, media_type, source_media_path, caption, moderation_status, processing_status, is_safe)
           VALUES(%s, 'IMAGE', %s, 'Dangerous', 'REVIEW', 'REVIEW', FALSE)
           RETURNING post_id""",
        (cid, src_key),
    )
    post_id = cur.fetchone()["post_id"]

    cur.execute(
        """INSERT INTO moderation_events(child_id, content_type, content_id, decision, status)
           VALUES(%s, 'IMAGE', %s, 'REVIEW', 'OPEN')
           RETURNING event_id""",
        (cid, post_id),
    )
    event_id = cur.fetchone()["event_id"]

    quarantine_cleaned = []

    def fake_cleanup(p_id, key):
        quarantine_cleaned.append(key)
        return True

    with patch("services.media_processor.block_and_cleanup_quarantine", side_effect=fake_cleanup):
        ok, result = _resolve_parent_review(pid, event_id, "BLOCK")
        assert ok is True
        assert result == "BLOCK"

    # Post must be BLOCKED in DB with media_path NULL
    cur.execute("SELECT moderation_status, processing_status, is_safe, media_path FROM posts WHERE post_id=%s", (post_id,))
    post = cur.fetchone()
    assert post["moderation_status"] == "BLOCKED"
    assert post["processing_status"] == "BLOCKED"
    assert post["is_safe"] is False
    assert post["media_path"] is None

    # Event resolved
    cur.execute("SELECT status FROM moderation_events WHERE event_id=%s", (event_id,))
    assert cur.fetchone()["status"] == "RESOLVED"

    # Quarantine cleanup called after DB commit
    assert src_key in quarantine_cleaned


# ============================================================================
# 7. CLEANUP FAILURE ENQUEUES TO OUTBOX
# ============================================================================

def test_quarantine_cleanup_failure_enqueues_to_media_outbox(db):
    user = _random_user(db, "CHILD")
    uid = user["user_id"]
    cur = db.cursor()
    bad_key = f"uploads/r2/quarantine/{uuid.uuid4().hex}.jpg"

    cur.execute(
        """INSERT INTO posts(child_id, media_type, source_media_path, caption, moderation_status, processing_status)
           VALUES(%s, 'IMAGE', %s, 'Cleanup fail', 'BLOCKED', 'BLOCKED')
           RETURNING post_id""",
        (uid, bad_key),
    )
    post_id = cur.fetchone()["post_id"]

    outbox_entries = []

    def fake_enqueue_delete(key, table, row_id):
        outbox_entries.append({"key": key, "table": table, "id": row_id})

    with patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.delete_reference", side_effect=RuntimeError("R2 500 internal error")), \
         patch("services.media_outbox.enqueue_delete", side_effect=fake_enqueue_delete):

        cleaned = media_processor.block_and_cleanup_quarantine(post_id, bad_key)
        assert cleaned is False
        assert len(outbox_entries) == 1
        assert outbox_entries[0]["key"] == bad_key
        assert outbox_entries[0]["id"] == post_id
