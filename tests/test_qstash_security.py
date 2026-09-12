"""Security and contract tests for Upstash QStash job queue and signature verification.

Verifies the official Upstash claim contract:
- iss == "Upstash"
- sub == canonical destination URL
- exp == valid, not expired
- nbf == valid, not in future
- body == SHA-256 base64url hash of the raw request body
- Current and next signing key support (key rotation)
- Defense-in-depth AI_SHARED_SECRET forwarding and verification
- Fail-closed production queue provider gating
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import time
from unittest.mock import patch, MagicMock

import jwt
import pytest

from services.job_queue import LocalJobQueue, QStashJobQueue, get_job_queue, validate_job_queue_config
from services.qstash_verifier import verify_qstash_signature


CANONICAL_URL = "https://modal.littlenet.ai/ai/jobs/process-media"
CURRENT_KEY = "sig_current_key_12345678901234567890"
NEXT_KEY = "sig_next_key_987654321098765432109876"


def _make_jwt(
    body: bytes | str,
    key: str,
    iss: str = "Upstash",
    sub: str | None = None,
    exp_offset: int = 300,
    nbf_offset: int = -10,
    tamper_body_claim: bool = False,
) -> str:
    raw_bytes = body.encode("utf-8") if isinstance(body, str) else body
    digest = hashlib.sha256(raw_bytes).digest()
    b64url = base64.urlsafe_b64encode(digest).decode("utf-8").rstrip("=")
    if tamper_body_claim:
        b64url = "invalid_hash_claim"
    payload = {
        "iss": iss,
        "sub": sub or CANONICAL_URL,
        "exp": int(time.time()) + exp_offset,
        "nbf": int(time.time()) + nbf_offset,
        "body": b64url,
    }
    return jwt.encode(payload, key, algorithm="HS256")


# ────────────────────────────────────────────────────────────────────────────
# 1-9: Explicit Official QStash Signature Semantics
# ────────────────────────────────────────────────────────────────────────────

def test_1_valid_official_qstash_signature_accepted():
    body = b'{"job_type": "process_media", "payload": {"post_id": 101}}'
    sig = _make_jwt(body, CURRENT_KEY, sub=CANONICAL_URL)
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is True


def test_2_missing_signature_rejected():
    body = b'{"test": 1}'
    assert verify_qstash_signature(body, "", CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


def test_3_invalid_signature_rejected():
    body = b'{"test": 1}'
    assert verify_qstash_signature(body, "invalid.jwt.token", CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


def test_4_expired_jwt_rejected():
    body = b'{"test": 1}'
    sig = _make_jwt(body, CURRENT_KEY, sub=CANONICAL_URL, exp_offset=-100)
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


def test_5_nbf_in_future_rejected():
    body = b'{"test": 1}'
    # nbf is 2000 seconds in future (exceeding tolerance)
    sig = _make_jwt(body, CURRENT_KEY, sub=CANONICAL_URL, nbf_offset=2000)
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


def test_6_wrong_sub_destination_url_rejected():
    body = b'{"test": 1}'
    sig = _make_jwt(body, CURRENT_KEY, sub="https://attacker.host/ai/jobs/process-media")
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


def test_7_changed_raw_body_rejected():
    original_body = b'{"post_id": 100, "child_id": 5}'
    tampered_body = b'{"post_id": 999, "child_id": 5}'
    sig = _make_jwt(original_body, CURRENT_KEY, sub=CANONICAL_URL)
    assert verify_qstash_signature(tampered_body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


def test_8_current_signing_key_accepted():
    body = b'{"item": "current_key_test"}'
    sig = _make_jwt(body, CURRENT_KEY, sub=CANONICAL_URL)
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is True


def test_9_next_signing_key_accepted_for_rotation():
    body = b'{"item": "next_key_test"}'
    sig = _make_jwt(body, NEXT_KEY, sub=CANONICAL_URL)
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is True


def test_wrong_signing_key_rejected():
    body = b'{"item": "wrong_key"}'
    sig = _make_jwt(body, "completely_wrong_key_1234567890123456", sub=CANONICAL_URL)
    assert verify_qstash_signature(body, sig, CURRENT_KEY, NEXT_KEY, url=CANONICAL_URL) is False


# ────────────────────────────────────────────────────────────────────────────
# 10-12: AI_SHARED_SECRET Forwarding and Defense in Depth
# ────────────────────────────────────────────────────────────────────────────

def test_10_ai_shared_secret_forwarded_correctly_when_publishing():
    """QStashJobQueue must forward AI_SHARED_SECRET via Upstash-Forward header."""
    q = QStashJobQueue(token="qstash_token_xyz", endpoint_url=CANONICAL_URL)
    payload = {"post_id": 1, "child_id": 2, "object_key": "k"}

    with patch.dict(os.environ, {"AI_SHARED_SECRET": "secret_ai_token_456"}), \
         patch("requests.post") as mock_post:
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"messageId": "msg_123"}
        mock_resp.raise_for_status.return_value = None
        mock_post.return_value = mock_resp

        q.enqueue("process_media", payload, deduplication_id="dedup_01")

        assert mock_post.called
        call_args = mock_post.call_args
        headers = call_args[1]["headers"]

        # Token must be in Upstash-Forward header, NOT exposed in JSON body or missing
        assert headers.get("Upstash-Forward-X-LittleNet-AI-Key") == "secret_ai_token_456"
        assert headers.get("Upstash-Deduplication-Id") == "dedup_01"
        assert "secret_ai_token_456" not in call_args[1]["data"]


def test_11_valid_qstash_signature_but_invalid_ai_shared_secret_rejected():
    """If Modal has AI_SHARED_SECRET configured, mismatched secret must be rejected with 401."""
    from ai_server import app
    client = app.test_client()

    body = json.dumps({"payload": {"post_id": 88, "child_id": 9, "object_key": "k", "kind": "post"}}).encode("utf-8")
    sig = _make_jwt(body, CURRENT_KEY, sub=CANONICAL_URL)

    env = {
        "QSTASH_CURRENT_SIGNING_KEY": CURRENT_KEY,
        "QSTASH_MODAL_ENDPOINT": CANONICAL_URL,
        "AI_SHARED_SECRET": "modal_strict_secret",
    }
    with patch.dict(os.environ, env):
        # Request has valid QStash signature, but wrong X-LittleNet-AI-Key
        resp = client.post(
            "/ai/jobs/process-media",
            data=body,
            headers={
                "Content-Type": "application/json",
                "Upstash-Signature": sig,
                "X-LittleNet-AI-Key": "wrong_secret_attacker",
            },
        )
        assert resp.status_code == 401
        assert resp.get_json()["error"] == "unauthorized"


def test_12_arbitrary_direct_public_post_cannot_trigger_processing():
    """Public arbitrary POST with no signature and no secret must be rejected."""
    from ai_server import app
    client = app.test_client()

    with patch.dict(os.environ, {"QSTASH_CURRENT_SIGNING_KEY": CURRENT_KEY}):
        resp = client.post(
            "/ai/jobs/process-media",
            data=b'{"post_id": 1, "child_id": 2, "object_key": "k"}',
            headers={"Content-Type": "application/json"},
        )
        assert resp.status_code == 401
        assert resp.get_json()["error"] == "unauthorized"


def test_ai_server_accepts_valid_signature_and_forwarded_secret():
    """Valid QStash signature + matching forwarded secret must trigger processing."""
    from ai_server import app
    client = app.test_client()

    body = json.dumps({"payload": {"post_id": 777, "child_id": 88, "object_key": "uploads/r2/k.mp4", "kind": "reel"}}).encode("utf-8")
    sig = _make_jwt(body, CURRENT_KEY, sub=CANONICAL_URL)

    env = {
        "QSTASH_CURRENT_SIGNING_KEY": CURRENT_KEY,
        "QSTASH_NEXT_SIGNING_KEY": NEXT_KEY,
        "QSTASH_MODAL_ENDPOINT": CANONICAL_URL,
        "AI_SHARED_SECRET": "modal_strict_secret",
    }
    with patch.dict(os.environ, env), \
         patch("services.media_processor.process_media_job") as mock_proc:
        mock_proc.return_value = {"ok": True, "status": "ALLOWED"}

        resp = client.post(
            "/ai/jobs/process-media",
            data=body,
            headers={
                "Content-Type": "application/json",
                "Upstash-Signature": sig,
                "X-LittleNet-AI-Key": "modal_strict_secret",
            },
        )
        assert resp.status_code == 200
        assert resp.get_json()["ok"] is True
        mock_proc.assert_called_once_with(777, 88, "uploads/r2/k.mp4", "reel")


# ────────────────────────────────────────────────────────────────────────────
# Queue Provider & Fail-Closed Rules
# ────────────────────────────────────────────────────────────────────────────

def test_job_queue_dev_allows_local():
    with patch.dict(os.environ, {"JOB_QUEUE_PROVIDER": "local"}, clear=False):
        assert validate_job_queue_config(is_production=False) == "local"
        q = get_job_queue()
        assert isinstance(q, LocalJobQueue)


def test_job_queue_dev_allows_qstash():
    env = {
        "JOB_QUEUE_PROVIDER": "qstash",
        "QSTASH_TOKEN": "token_123",
        "QSTASH_MODAL_ENDPOINT": "https://modal.run/test",
    }
    with patch.dict(os.environ, env, clear=False):
        assert validate_job_queue_config(is_production=False) == "qstash"


def test_job_queue_prod_fails_closed_when_provider_missing():
    with patch.dict(os.environ, {}, clear=True):
        with pytest.raises(RuntimeError, match="JOB_QUEUE_PROVIDER is required and must be 'qstash'"):
            validate_job_queue_config(is_production=True)


def test_job_queue_prod_fails_closed_when_local():
    with patch.dict(os.environ, {"JOB_QUEUE_PROVIDER": "local"}, clear=True):
        with pytest.raises(RuntimeError, match="LocalJobQueue is forbidden in production"):
            validate_job_queue_config(is_production=True)


def test_job_queue_prod_fails_closed_when_token_missing():
    env = {
        "JOB_QUEUE_PROVIDER": "qstash",
        "QSTASH_MODAL_ENDPOINT": "https://modal.run/test",
    }
    with patch.dict(os.environ, env, clear=True):
        with pytest.raises(RuntimeError, match="QSTASH_TOKEN is required"):
            validate_job_queue_config(is_production=True)


def test_job_queue_prod_fails_closed_when_endpoint_missing():
    env = {
        "JOB_QUEUE_PROVIDER": "qstash",
        "QSTASH_TOKEN": "tok_abc",
    }
    with patch.dict(os.environ, env, clear=True):
        with pytest.raises(RuntimeError, match="QSTASH_MODAL_ENDPOINT is required"):
            validate_job_queue_config(is_production=True)


def test_job_queue_prod_succeeds_when_fully_configured():
    env = {
        "JOB_QUEUE_PROVIDER": "qstash",
        "QSTASH_TOKEN": "tok_valid",
        "QSTASH_MODAL_ENDPOINT": "https://modal.run/test",
    }
    with patch.dict(os.environ, env, clear=True):
        provider = validate_job_queue_config(is_production=True)
        assert provider == "qstash"
        q = get_job_queue()
        assert isinstance(q, QStashJobQueue)


def test_qstash_job_queue_uses_configured_regional_url():
    queue = QStashJobQueue("tok_secret_123", "https://modal.endpoint/job", base_url="https://qstash-eu-central-1.upstash.io")
    with patch("requests.post") as mock_post:
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"messageId": "msg_region_1"}
        mock_post.return_value = mock_resp

        msg_id = queue.enqueue("media_proc", {"item": 1}, deduplication_id="dedup_1")
        assert msg_id == "msg_region_1"
        assert mock_post.call_args[0][0] == "https://qstash-eu-central-1.upstash.io/v2/publish/https://modal.endpoint/job"


def test_qstash_job_queue_uses_default_when_url_absent():
    with patch.dict(os.environ, {}, clear=True):
        queue = QStashJobQueue("tok_secret_456", "https://modal.endpoint/job")
        with patch("requests.post") as mock_post:
            mock_resp = MagicMock()
            mock_resp.json.return_value = {"messageId": "msg_default_1"}
            mock_post.return_value = mock_resp

            msg_id = queue.enqueue("media_proc", {"item": 2})
            assert msg_id == "msg_default_1"
            assert mock_post.call_args[0][0] == "https://qstash.upstash.io/v2/publish/https://modal.endpoint/job"


def test_qstash_job_queue_token_and_secret_redacted_on_failure():
    secret_token = "super_sensitive_token_xyz999"
    secret_ai = "super_sensitive_ai_secret_abc111"
    queue = QStashJobQueue(secret_token, "https://modal.endpoint/job")
    with patch.dict(os.environ, {"AI_SHARED_SECRET": secret_ai}), \
         patch("requests.post") as mock_post:
        mock_post.side_effect = Exception(f"Connection failed for {secret_token} and {secret_ai}")

        with pytest.raises(RuntimeError) as exc_info:
            queue.enqueue("media_proc", {"item": 3})

        err_str = str(exc_info.value)
        assert secret_token not in err_str
        assert secret_ai not in err_str
        assert "[REDACTED]" in err_str


def test_qstash_job_queue_forwards_ai_shared_secret():
    queue = QStashJobQueue("tok_abc", "https://modal.endpoint/job")
    with patch.dict(os.environ, {"AI_SHARED_SECRET": "test_ai_secret_777"}), \
         patch("requests.post") as mock_post:
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"messageId": "msg_fwd_1"}
        mock_post.return_value = mock_resp

        queue.enqueue("media_proc", {"test": True})
        headers = mock_post.call_args[1]["headers"]
        assert headers.get("Upstash-Forward-X-LittleNet-AI-Key") == "test_ai_secret_777"
        assert headers.get("Authorization") == "Bearer tok_abc"

