"""Security and contract tests for Upstash QStash job queue and signature verification."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import time
from unittest.mock import patch

import jwt
import pytest

from services.job_queue import LocalJobQueue, QStashJobQueue, get_job_queue, validate_job_queue_config
from services.qstash_verifier import verify_qstash_signature


def _make_jwt(
    body: bytes,
    key: str,
    iss: str = "Upstash",
    sub: str | None = None,
    exp_offset: int = 300,
    tamper_body_claim: bool = False,
) -> str:
    digest = hashlib.sha256(body).digest()
    b64url = base64.urlsafe_b64encode(digest).decode("utf-8").rstrip("=")
    if tamper_body_claim:
        b64url = "invalid_hash_claim"
    payload = {
        "iss": iss,
        "exp": int(time.time()) + exp_offset,
        "nbf": int(time.time()) - 10,
        "body": b64url,
    }
    if sub:
        payload["sub"] = sub
    return jwt.encode(payload, key, algorithm="HS256")


def test_qstash_signature_missing_rejected():
    assert verify_qstash_signature(b"{}", "", "sig_key_1_1234567890_1234567890_1234") is False


def test_qstash_signature_invalid_rejected():
    assert verify_qstash_signature(b"{}", "invalid.jwt.signature", "sig_key_1_1234567890_1234567890_1234") is False


def test_qstash_signature_valid_current_key_accepted():
    key1 = "current_key_secret_1234567890123456"
    key2 = "next_key_secret_1234567890123456789"
    body = json.dumps({"job": "proc", "id": 123}).encode("utf-8")
    sig = _make_jwt(body, key1)
    assert verify_qstash_signature(body, sig, key1, key2) is True


def test_qstash_signature_valid_next_key_accepted_for_rotation():
    key1 = "current_key_secret_1234567890123456"
    key2 = "next_key_secret_1234567890123456789"
    body = json.dumps({"job": "proc", "id": 456}).encode("utf-8")
    sig = _make_jwt(body, key2)
    assert verify_qstash_signature(body, sig, key1, key2) is True


def test_qstash_signature_wrong_key_rejected():
    key1 = "current_key_secret_1234567890123456"
    key2 = "next_key_secret_1234567890123456789"
    body = b"sample_payload"
    sig = _make_jwt(body, "wrong_key_12345678901234567890123456")
    assert verify_qstash_signature(body, sig, key1, key2) is False


def test_qstash_signature_tampered_body_rejected():
    key = "current_key_secret_1234567890123456"
    original_body = b'{"post_id": 1}'
    tampered_body = b'{"post_id": 999}'
    sig = _make_jwt(original_body, key)
    assert verify_qstash_signature(tampered_body, sig, key) is False


def test_qstash_signature_expired_token_rejected():
    key = "current_key_secret_1234567890123456"
    body = b'{"post_id": 1}'
    sig = _make_jwt(body, key, exp_offset=-1000)
    assert verify_qstash_signature(body, sig, key) is False


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


# ────────────────────────────────────────────────────────────────────────────
# Receiver Endpoint In ai_server.py
# ────────────────────────────────────────────────────────────────────────────

def test_ai_server_process_media_rejects_unsigned_request():
    from ai_server import app
    client = app.test_client()

    resp = client.post("/ai/jobs/process-media", json={"post_id": 1, "child_id": 2, "object_key": "k"})
    assert resp.status_code == 401
    assert "unauthorized" in resp.get_json().get("error", "")


def test_ai_server_process_media_accepts_valid_qstash_signature():
    from ai_server import app
    client = app.test_client()

    sig_key = "test_sig_key_1234567890123456789012"
    body = json.dumps({"payload": {"post_id": 9999, "child_id": 10, "object_key": "k", "kind": "post"}}).encode("utf-8")
    sig = _make_jwt(body, sig_key)

    with patch.dict(os.environ, {"QSTASH_CURRENT_SIGNING_KEY": sig_key}), \
         patch("services.media_processor.process_media_job") as mock_proc:
        mock_proc.return_value = {"ok": True, "status": "ALLOWED"}

        resp = client.post(
            "/ai/jobs/process-media",
            data=body,
            headers={"Content-Type": "application/json", "Upstash-Signature": sig},
        )
        assert resp.status_code == 200
        assert resp.get_json()["ok"] is True
        mock_proc.assert_called_once_with(9999, 10, "k", "post")
