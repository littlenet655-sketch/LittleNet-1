import os
import json
import hashlib
import hmac
from datetime import datetime, timedelta, timezone
import pytest
from io import BytesIO
from unittest.mock import patch, MagicMock
from app import app
from mobile.api import _issue_token, _media_allowed, _resolve_parent_review
import safety.face_service as face_service
import services.media_processor as media_processor
from services import object_storage


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def _parent_headers(user_id=101):
    token = _issue_token({"user_id": user_id, "role": "PARENT", "full_name": "Test Parent"})
    return {"Authorization": f"Bearer {token}"}


def _child_headers(user_id=202):
    token = _issue_token({"user_id": user_id, "role": "CHILD", "full_name": "Test Child"})
    return {"Authorization": f"Bearer {token}"}


def _valid_vector(dim=512, val=0.05):
    return [val] * dim


# ============================================================================
# 1. FAIL-CLOSED FACE ENROLLMENT & VALIDATION
# ============================================================================

def test_validated_embedding_rejects_empty_and_invalid():
    with pytest.raises(ValueError, match="embedding_missing"):
        face_service._validated_embedding([])

    with pytest.raises(ValueError, match="embedding_missing"):
        face_service._validated_embedding(None)

    # Rejection of <512 and >512 dimensions (including 128, 511, 513)
    with pytest.raises(ValueError, match="invalid_embedding_dimensions"):
        face_service._validated_embedding([0.1] * 64)

    with pytest.raises(ValueError, match="invalid_embedding_dimensions"):
        face_service._validated_embedding([0.1] * 128)

    with pytest.raises(ValueError, match="invalid_embedding_dimensions"):
        face_service._validated_embedding([0.1] * 511)

    with pytest.raises(ValueError, match="invalid_embedding_dimensions"):
        face_service._validated_embedding([0.1] * 513)

    # Non-finite values: NaN, Infinity
    with pytest.raises(ValueError, match="embedding_invalid"):
        face_service._validated_embedding([float('nan')] * 512)

    with pytest.raises(ValueError, match="embedding_invalid"):
        face_service._validated_embedding([float('inf')] * 512)

    with pytest.raises(ValueError, match="embedding_invalid"):
        face_service._validated_embedding([float('-inf')] * 512)

    # Zero vector
    with pytest.raises(ValueError, match="embedding_invalid"):
        face_service._validated_embedding([0.0] * 512)

    # Booleans and strings
    with pytest.raises(ValueError, match="embedding_invalid"):
        face_service._validated_embedding([True] * 512)

    with pytest.raises(ValueError, match="embedding_invalid"):
        face_service._validated_embedding(["bad_string"] * 512)


def test_enroll_and_verify_model_name_enforcement():
    # Enroll rejects wrong model
    with pytest.raises(ValueError, match="invalid_model_name"):
        face_service.enroll(202, "dummy_path.jpg", model_name="VGG-Face")

    # Verify rejects wrong model in profile
    with patch("safety.face_service.fetch_one", return_value={"embedding": _valid_vector(), "model_name": "VGG-Face"}), \
         patch("safety.face_service.execute") as mock_exec:
        match, reason, dist = face_service.verify(202, "dummy.jpg")
        assert match is False
        assert reason == "invalid_enrolled_model"
        mock_exec.assert_called_once()
        assert "invalid_enrolled_model" in mock_exec.call_args[0][1]

    # Verify rejects malformed JSON
    with patch("safety.face_service.fetch_one", return_value={"embedding": "{not_valid_json", "model_name": "Facenet512"}), \
         patch("safety.face_service.execute") as mock_exec:
        match, reason, dist = face_service.verify(202, "dummy.jpg")
        assert match is False
        assert reason == "invalid_enrolled_embedding"


def test_validated_embedding_accepts_valid_vector():
    vec = [0.1] * 512
    out = face_service._validated_embedding(vec)
    assert len(out) == 512
    assert out[0] == 0.1


def test_enroll_fails_closed_on_empty_or_spoof():
    with patch("safety.face_service._embedding", side_effect=ValueError("liveness_failed")):
        with pytest.raises(ValueError, match="liveness_failed"):
            face_service.enroll(202, "dummy_path.jpg")

    with patch("safety.face_service._embedding", return_value=[]):
        with pytest.raises(ValueError, match="embedding_missing"):
            face_service.enroll(202, "dummy_path.jpg")


def test_enroll_persists_valid_facenet512_embedding():
    vec = _valid_vector()
    with patch("safety.face_service._embedding", return_value=vec), \
         patch("safety.face_service.execute") as mock_exec:
        ok = face_service.enroll(202, "dummy_path.jpg")
        assert ok is True
        mock_exec.assert_called_once()
        args = mock_exec.call_args[0]
        assert "INSERT INTO face_profiles" in args[0]
        assert args[1][0] == 202
        assert json.loads(args[1][1]) == vec



def test_child_gate_blocks_invalid_or_missing_face_profile(client):
    headers = _child_headers(202)

    # 1. Child with no profile row
    with patch("mobile.api.fetch_one") as mock_fetch:
        mock_fetch.side_effect = [
            {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE", "age": 10, "is_approved": True},
            None,  # face_profiles query -> None
        ]
        res = client.get("/api/mobile/v2/kids/feed", headers=headers)
        assert res.status_code == 428
        assert res.get_json()["error"] == "face_enrollment_required"

    # 2. Child with empty [] profile row
    with patch("mobile.api.fetch_one") as mock_fetch:
        mock_fetch.side_effect = [
            {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE", "age": 10, "is_approved": True},
            {"embedding": []},  # dummy empty embedding
        ]
        res = client.get("/api/mobile/v2/kids/feed", headers=headers)
        assert res.status_code == 428
        assert res.get_json()["error"] == "face_enrollment_required"


# ============================================================================
# 2. CHILD FACE-FIRST AUTHENTICATION MATRIX
# ============================================================================

def test_verify_fails_closed_on_corrupt_stored_profile():
    with patch("safety.face_service.fetch_one", return_value={"embedding": [], "model_name": "Facenet512"}), \
         patch("safety.face_service.execute"):
        match, reason, dist = face_service.verify(202, "dummy.jpg")
        assert match is False
        assert reason == "invalid_enrolled_embedding"

    with patch("safety.face_service.fetch_one", return_value={"embedding": [0.0] * 512, "model_name": "Facenet512"}), \
         patch("safety.face_service.execute"):
        match, reason, dist = face_service.verify(202, "dummy.jpg")
        assert match is False
        assert reason == "invalid_enrolled_embedding"


def test_verify_liveness_failure():
    with patch("safety.face_service.fetch_one", return_value={"embedding": _valid_vector(), "model_name": "Facenet512"}), \
         patch("safety.remote_client.enabled", return_value=False), \
         patch("safety.face_service._embedding", side_effect=ValueError("liveness_failed")), \
         patch("safety.face_service.execute"):
        match, reason, dist = face_service.verify(202, "dummy.jpg")
        assert match is False
        assert reason == "liveness_failed"


def test_verify_match_and_mismatch():
    enrolled = _valid_vector(val=0.05)
    with patch("safety.face_service.fetch_one", return_value={"embedding": enrolled, "model_name": "Facenet512"}), \
         patch("safety.remote_client.enabled", return_value=False), \
         patch("safety.face_service.execute"):

        # Match case
        with patch("safety.face_service._embedding", return_value=enrolled):
            match, reason, dist = face_service.verify(202, "dummy.jpg")
            assert match is True
            assert reason == "matched"
            assert dist is not None and dist < 0.35

        # Mismatch case
        diff_vec = [-0.05] * 512
        with patch("safety.face_service._embedding", return_value=diff_vec):
            match, reason, dist = face_service.verify(202, "dummy.jpg")
            assert match is False
            assert reason == "not_matched"


def test_child_face_login_endpoint(client):
    user_row = {
        "user_id": 202,
        "username": "kiddo",
        "email": "kid@example.com",
        "role": "CHILD",
        "account_status": "ACTIVE",
        "full_name": "Test Kid",
        "parent_id": 101,
        "age": 10,
        "is_approved": True,
    }
    challenge = {
        "challenge_id": "550e8400-e29b-41d4-a716-446655440001",
        "user_id": 202,
        "nonce": "fresh-nonce",
        "action": "BLINK",
        "used_at": None,
        "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
    }

    def face_fetch(query, params=()):
        if "FROM face_auth_challenges" in query:
            return challenge
        return user_row

    def consume_challenge(query, params=(), returning=False):
        return {"challenge_id": challenge["challenge_id"]} if "UPDATE face_auth_challenges" in query else None

    def request_data():
        return {
            "identifier": "kiddo",
            "mode": "kids",
            "challenge_id": challenge["challenge_id"],
            "nonce": challenge["nonce"],
            "action_completed": challenge["action"],
            "photo": (BytesIO(b"image_bytes" * 20), "selfie.jpg"),
        }

    # 1. Un-enrolled child -> 404 not_enrolled
    with patch("mobile.api.fetch_one", side_effect=face_fetch), \
         patch("mobile.api.execute", side_effect=consume_challenge), \
         patch("mobile.api.verify", return_value=(False, "not_enrolled", None)):
        res = client.post("/api/mobile/v1/auth/face-login", data=request_data(), content_type="multipart/form-data")
        assert res.status_code == 404
        assert res.get_json()["reason"] == "not_enrolled"

    # 2. Liveness / spoof failure -> 401
    with patch("mobile.api.fetch_one", side_effect=face_fetch), \
         patch("mobile.api.execute", side_effect=consume_challenge), \
         patch("mobile.api.verify", return_value=(False, "liveness_failed", None)):
        res = client.post("/api/mobile/v1/auth/face-login", data=request_data(), content_type="multipart/form-data")
        assert res.status_code == 401
        assert res.get_json()["reason"] == "liveness_failed"

    # 3. Invalid enrolled embedding -> 401
    with patch("mobile.api.fetch_one", side_effect=face_fetch), \
         patch("mobile.api.execute", side_effect=consume_challenge), \
         patch("mobile.api.verify", return_value=(False, "invalid_enrolled_embedding", None)):
        res = client.post("/api/mobile/v1/auth/face-login", data=request_data(), content_type="multipart/form-data")
        assert res.status_code == 401
        assert res.get_json()["reason"] == "invalid_enrolled_embedding"

    # 4. Genuine face match -> 200 with tokens
    with patch("mobile.api.fetch_one") as mock_fetch, \
         patch("mobile.api.verify", return_value=(True, "matched", 0.15)), \
         patch("mobile.api.start_session", return_value={"session_key": "sess_123"}), \
         patch("mobile.api.execute", side_effect=consume_challenge):
        mock_fetch.side_effect = [
            user_row, # user lookup
            challenge,
            {"embedding": _valid_vector()}, # profile check
            None, # quiz check
        ]
        res = client.post("/api/mobile/v1/auth/face-login", data=request_data(), content_type="multipart/form-data")
        assert res.status_code == 200
        body = res.get_json()
        assert body["ok"] is True
        assert body["auth_method"] == "FACE"
        assert "token" in body


def test_device_biometric_challenge_does_not_claim_to_be_face(client):
    challenge_id = "550e8400-e29b-41d4-a716-446655440000"
    nonce = "abcd1234efgh5678"
    action = "BLINK"
    user_id = 202
    biometric_key = "device_key_secret_123"

    challenge_row = {
        "challenge_id": challenge_id,
        "user_id": user_id,
        "nonce": nonce,
        "action": action,
        "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
        "used_at": None,
    }
    user_row = {
        "user_id": user_id,
        "username": "kiddo",
        "email": "kid@example.com",
        "role": "CHILD",
        "account_status": "ACTIVE",
        "full_name": "Test Kid",
        "parent_id": 101,
        "age": 10,
        "is_approved": True,
    }

    # Generate expected HMAC signature
    msg = f"{challenge_id}:{nonce}:{action}:{user_id}".encode("utf-8")
    sig = hmac.new(biometric_key.encode("utf-8"), msg, hashlib.sha256).hexdigest().lower()

    with patch("mobile.api.fetch_one") as mock_fetch, \
         patch("mobile.api.start_session", return_value={"session_key": "sess_123"}), \
         patch("mobile.api.execute"):
        mock_fetch.side_effect = [
            challenge_row, # challenge lookup
            {"biometric_key": biometric_key}, # face_profiles biometric_key
            user_row, # user lookup
            {"embedding": _valid_vector()}, # face profile check for gate
            None, # quiz check
        ]
        payload = {
            "challenge_id": challenge_id,
            "nonce": nonce,
            "action_completed": action,
            "signature": sig,
        }
        res = client.post("/api/mobile/v1/auth/face/verify-challenge", json=payload)
        assert res.status_code == 200
        body = res.get_json()
        assert body["ok"] is True
        assert body["auth_method"] == "DEVICE_BIOMETRIC_CHALLENGE"



# ============================================================================
# 3. V2 UPLOAD STATE MACHINE & IDEMPOTENCY
# ============================================================================

def test_v2_upload_complete_size_and_mime_validation(client):
    headers = _child_headers(202)
    session_data = {
        "upload_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "child_id": 202,
        "object_key": "uploads/r2/quarantine/202/pic.jpg",
        "media_type": "IMAGE",
        "kind": "POST",
        "expected_size_bytes": 1000,
        "mime_type": "image/jpeg",
        "status": "PENDING",
        "expires_at": datetime.now(timezone.utc) + timedelta(hours=1),
    }

    # 1. R2 object size mismatch
    with patch("mobile.api.fetch_one") as mock_fetch, \
         patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.head_object", return_value={"content_length": 500, "content_type": "image/jpeg"}), \
         patch("mobile.api.get_db_connection") as mock_conn:

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            session_data, # upload session row
            None, # existing post check
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        mock_fetch.side_effect = [
            {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE", "age": 10, "is_approved": True}, # auth
            {"embedding": _valid_vector(), "model_name": "Facenet512"}, # face gate
        ]
        res = client.post(f"/api/mobile/v2/uploads/{session_data['upload_id']}/complete", headers=headers, json={})
        assert res.status_code == 400
        assert res.get_json()["error"] == "media_size_mismatch"

    # 2. R2 MIME type mismatch
    with patch("mobile.api.fetch_one") as mock_fetch, \
         patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.head_object", return_value={"content_length": 1000, "content_type": "text/html"}), \
         patch("mobile.api.get_db_connection") as mock_conn:

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            session_data, # upload session row
            None, # existing post check
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        mock_fetch.side_effect = [
            {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE", "age": 10, "is_approved": True}, # auth
            {"embedding": _valid_vector(), "model_name": "Facenet512"}, # face gate
        ]
        res = client.post(f"/api/mobile/v2/uploads/{session_data['upload_id']}/complete", headers=headers, json={})
        assert res.status_code == 400
        assert res.get_json()["error"] == "media_mime_mismatch"



def test_v2_upload_complete_queue_spawn_failure_retryable_503(client):
    headers = _child_headers(202)
    session_data = {
        "upload_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "child_id": 202,
        "object_key": "uploads/r2/quarantine/202/pic.jpg",
        "media_type": "IMAGE",
        "kind": "POST",
        "expected_size_bytes": 1000,
        "mime_type": "image/jpeg",
        "status": "PENDING",
        "expires_at": datetime.now(timezone.utc) + timedelta(hours=1),
    }

    with patch("mobile.api.fetch_one") as mock_fetch, \
         patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.head_object", return_value={"content_length": 1000, "content_type": "image/jpeg"}), \
         patch("services.job_queue.enqueue_media_job", side_effect=RuntimeError("Modal queue unreachable")), \
         patch("mobile.api.get_db_connection") as mock_conn:

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            session_data, # upload session row
            None, # existing post check (None)
            {"post_id": 501}, # post insert RETURNING post_id
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        mock_fetch.side_effect = [
            {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE", "age": 10, "is_approved": True}, # auth
            {"embedding": _valid_vector(), "model_name": "Facenet512"}, # face gate
        ]
        res = client.post(f"/api/mobile/v2/uploads/{session_data['upload_id']}/complete", headers=headers, json={})
        assert res.status_code == 503
        data = res.get_json()
        assert data["error"] == "job_dispatch_failed"
        assert data["retryable"] is True
        assert data["post_id"] == 501


def test_v2_upload_complete_idempotent_retry(client):
    headers = _child_headers(202)
    session_data = {
        "upload_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "child_id": 202,
        "object_key": "uploads/r2/quarantine/202/pic.jpg",
        "media_type": "IMAGE",
        "kind": "POST",
        "expected_size_bytes": 1000,
        "mime_type": "image/jpeg",
        "status": "CONSUMED",
        "expires_at": datetime.now(timezone.utc) + timedelta(hours=1),
    }

    with patch("mobile.api.fetch_one") as mock_fetch, \
         patch("services.object_storage.enabled", return_value=True), \
         patch("services.object_storage.head_object", return_value={"content_length": 1000, "content_type": "image/jpeg"}), \
         patch("mobile.api.get_db_connection") as mock_conn:

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            session_data,
            {"post_id": 501, "source_media_path": "uploads/r2/quarantine/202/pic.jpg", "processing_status": "PROCESSING", "processing_error": None},
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        mock_fetch.side_effect = [
            {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE", "age": 10, "is_approved": True}, # auth
            {"embedding": _valid_vector(), "model_name": "Facenet512"}, # face gate
        ]
        res = client.post(f"/api/mobile/v2/uploads/{session_data['upload_id']}/complete", headers=headers, json={})
        assert res.status_code == 200
        data = res.get_json()
        assert data["ok"] is True
        assert data["post_id"] == 501
        assert data["status"] == "PROCESSING"
        assert data["idempotent"] is True



# ============================================================================
# 4. REVIEW LIFECYCLE & SANITIZATION FAIL-CLOSED
# ============================================================================

def test_media_allowed_blocks_quarantine_from_unauthorized_users():
    quarantine_ref = "uploads/r2/quarantine/202/pic.jpg"

    with patch("mobile.api.fetch_one") as mock_fetch:
        # 1. Post is in REVIEW / source_media_path is quarantine
        post_review = {
            "post_id": 501,
            "child_id": 202,
            "moderation_status": "REVIEW",
            "is_safe": False,
            "source_media_path": quarantine_ref,
            "media_path": quarantine_ref,
            "poster_path": None,
        }
        mock_fetch.return_value = post_review

        # Child viewer -> always blocked
        assert _media_allowed(303, "CHILD", quarantine_ref) is False

        # Parent who does NOT own child -> blocked
        with patch("mobile.api.owns", return_value=False):
            assert _media_allowed(102, "PARENT", quarantine_ref) is False

        # Parent who DOES own child -> allowed to preview
        with patch("mobile.api.owns", return_value=True):
            assert _media_allowed(101, "PARENT", quarantine_ref) is True

        # Admin -> allowed
        assert _media_allowed(999, "ADMIN", quarantine_ref) is True

    # 2. Post is BLOCKED -> strictly blocked for everyone
    with patch("mobile.api.fetch_one") as mock_fetch:
        mock_fetch.return_value = {
            "post_id": 502,
            "child_id": 202,
            "moderation_status": "BLOCKED",
            "is_safe": False,
            "source_media_path": quarantine_ref,
            "media_path": quarantine_ref,
            "poster_path": None,
        }
        assert _media_allowed(202, "CHILD", quarantine_ref) is False
        assert _media_allowed(101, "PARENT", quarantine_ref) is False
        assert _media_allowed(999, "ADMIN", quarantine_ref) is False


def test_sanitize_and_promote_media_fail_closed_on_corrupt_bytes():
    with patch("services.object_storage.download_file", side_effect=RuntimeError("Corrupt object data")):
        with pytest.raises(RuntimeError):
            media_processor.sanitize_and_promote_media(501, 202, "uploads/r2/quarantine/202/pic.jpg", "post", "IMAGE")


def test_resolve_parent_review_approval_promotes_media(client):
    headers = _parent_headers(101)
    event_id = 77
    post_id = 501

    with patch("mobile.api.get_db_connection") as mock_conn, \
         patch("mobile.api.owns", return_value=True), \
         patch("services.media_processor.sanitize_and_promote_media", return_value=("uploads/r2/published/202/clean.jpg", "uploads/r2/posters/202/clean.jpg")), \
         patch("services.media_processor._notify_approved_followers"), \
         patch("mobile.api.fetch_one", return_value={"user_id": 101, "role": "PARENT", "account_status": "ACTIVE"}):

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            {"event_id": event_id, "child_id": 202, "content_type": "IMAGE", "content_id": post_id, "decision": "REVIEW", "status": "OPEN"},
            {"post_id": post_id, "child_id": 202, "source_media_path": "uploads/r2/quarantine/202/pic.jpg", "media_type": "IMAGE"},
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        res = client.post(f"/api/mobile/v1/parent/safety/{event_id}", headers=headers, json={"action": "APPROVE"})
        assert res.status_code == 200
        assert res.get_json()["ok"] is True
        assert res.get_json()["result"] == "APPROVE"


def test_resolve_parent_review_sanitization_failure_fails_closed_to_blocked(client):
    headers = _parent_headers(101)
    event_id = 77
    post_id = 501

    with patch("mobile.api.get_db_connection") as mock_conn, \
         patch("mobile.api.owns", return_value=True), \
         patch("services.media_processor.sanitize_and_promote_media", side_effect=RuntimeError("FFmpeg transcode failed")), \
         patch("mobile.api.fetch_one", return_value={"user_id": 101, "role": "PARENT", "account_status": "ACTIVE"}):

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            {"event_id": event_id, "child_id": 202, "content_type": "IMAGE", "content_id": post_id, "decision": "REVIEW", "status": "OPEN"},
            {"post_id": post_id, "child_id": 202, "source_media_path": "uploads/r2/quarantine/202/pic.jpg", "media_type": "IMAGE"},
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        res = client.post(f"/api/mobile/v1/parent/safety/{event_id}", headers=headers, json={"action": "APPROVE"})
        assert res.status_code == 400
        assert res.get_json()["ok"] is False
        assert res.get_json()["result"] == "sanitization_failed"


def test_resolve_parent_review_block_deletes_quarantine(client):
    headers = _parent_headers(101)
    event_id = 77
    post_id = 501

    with patch("mobile.api.get_db_connection") as mock_conn, \
         patch("mobile.api.owns", return_value=True), \
         patch("services.media_processor.block_and_cleanup_quarantine") as mock_cleanup, \
         patch("mobile.api.fetch_one", return_value={"user_id": 101, "role": "PARENT", "account_status": "ACTIVE"}):

        mock_cur = MagicMock()
        mock_cur.fetchone.side_effect = [
            {"event_id": event_id, "child_id": 202, "content_type": "IMAGE", "content_id": post_id, "decision": "REVIEW", "status": "OPEN"},
            {"post_id": post_id, "child_id": 202, "source_media_path": "uploads/r2/quarantine/202/pic.jpg", "media_type": "IMAGE"},
        ]
        mock_conn.return_value.cursor.return_value = mock_cur

        res = client.post(f"/api/mobile/v1/parent/safety/{event_id}", headers=headers, json={"action": "BLOCK"})
        assert res.status_code == 200
        assert res.get_json()["ok"] is True
        assert res.get_json()["result"] == "BLOCK"
        mock_cleanup.assert_called_once_with(post_id, "uploads/r2/quarantine/202/pic.jpg")


def test_child_face_skip_rejected_with_403(client):
    headers = _child_headers(202)
    with patch("mobile.api.fetch_one", return_value={"user_id": 202, "role": "CHILD", "account_status": "ACTIVE"}), \
         patch("mobile.api.execute") as mock_exec:
        res = client.post("/api/mobile/v1/kids/face/skip", headers=headers)
        assert res.status_code == 403
        data = res.get_json()
        assert data["ok"] is False
        assert data["error"] == "parent_approval_required"
        mock_exec.assert_not_called()


def test_child_face_skip_does_not_update_db(client):
    headers = _child_headers(202)
    with patch("mobile.api.fetch_one", return_value={"user_id": 202, "role": "CHILD", "account_status": "ACTIVE"}), \
         patch("mobile.api.execute") as mock_exec:
        res = client.post("/api/mobile/v1/kids/face/skip", headers=headers)
        assert res.status_code == 403
        for call_args in mock_exec.call_args_list:
            assert "face_enrollment_skipped" not in str(call_args)


def test_normal_child_face_enrollment_endpoint(client):
    headers = _child_headers(202)
    dummy_img = BytesIO(b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"\x00" * 50)
    with patch("mobile.api.fetch_one", return_value={"user_id": 202, "role": "CHILD", "account_status": "ACTIVE"}), \
         patch("mobile.api.has_face_profile", return_value=False), \
         patch("mobile.api.enroll", return_value={"enrolled": True, "embedding": _valid_vector()}) as mock_enroll, \
         patch("mobile.api.execute") as mock_exec, \
         patch("mobile.api.needs_onboarding_quiz", return_value=False):
        res = client.post(
            "/api/mobile/v1/kids/face/enroll",
            headers=headers,
            data={"photo": (dummy_img, "face.jpg")},
            content_type="multipart/form-data",
        )
        assert res.status_code == 200
        data = res.get_json()
        assert data["ok"] is True
        assert "biometric_key" in data
        mock_enroll.assert_called_once()
        # Verify face_enrollment_skipped was set to FALSE on successful enrollment
        found_unskip = any("face_enrollment_skipped=FALSE" in str(c) for c in mock_exec.call_args_list)
        assert found_unskip is True

