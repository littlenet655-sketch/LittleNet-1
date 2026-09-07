import os
import tempfile
import urllib.error
from unittest.mock import MagicMock, patch
from pathlib import Path
from PIL import Image

import pytest


def test_verify_adult_face_fails_closed_on_dimensions_alone():
    """A valid 640x480 image without adult detection MUST NOT become is_adult=True."""
    from safety.face_service import verify_adult_face

    # Create a real valid 640x480 blank image
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        img = Image.new("RGB", (640, 480), color=(128, 128, 128))
        img.save(tmp.name, "JPEG")
        tmp_path = tmp.name

    try:
        # Without remote AI enabled, local DeepFace or unavailable fallback runs
        with patch.dict(os.environ, {"AI_SERVICE_URL": "", "GEMINI_API_KEY": "", "GOOGLE_API_KEY": ""}, clear=False):
            res = verify_adult_face(tmp_path)
            assert res.get("is_adult") is False
            assert res.get("estimated_age") is None
            assert res.get("method") != "LIVENESS_CAMERA"
            assert res.get("reason") in {"liveness_failed", "liveness_unavailable", "age_verification_unavailable"}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_verify_adult_face_blocks_under_18():
    """DeepFace or Gemini returning age < 18 must fail with reason 'under_age'."""
    from safety.face_service import verify_adult_face

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp.write(b"fake_image_bytes")
        tmp_path = tmp.name

    try:
        mock_deepface = MagicMock()
        mock_deepface.extract_faces.return_value = [{"is_real": True}]
        mock_deepface.analyze.return_value = [{"age": 15}]

        with patch.dict(os.environ, {"AI_SERVICE_URL": ""}, clear=False):
            with patch.dict("sys.modules", {"deepface": MagicMock(DeepFace=mock_deepface)}):
                res = verify_adult_face(tmp_path)
                assert res.get("is_adult") is False
                assert res.get("estimated_age") == 15
                assert res.get("reason") == "under_age"
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_verify_adult_face_blocks_liveness_failure():
    """Spoofed or failed liveness check must fail with reason 'liveness_failed'."""
    from safety.face_service import verify_adult_face

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp.write(b"fake_image_bytes")
        tmp_path = tmp.name

    try:
        mock_deepface = MagicMock()
        mock_deepface.extract_faces.return_value = [{"is_real": False}]

        with patch.dict(os.environ, {"AI_SERVICE_URL": ""}, clear=False):
            with patch.dict("sys.modules", {"deepface": MagicMock(DeepFace=mock_deepface)}):
                res = verify_adult_face(tmp_path)
                assert res.get("is_adult") is False
                assert res.get("reason") == "liveness_failed"
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_verify_adult_face_fails_closed_when_age_model_unavailable():
    """When no age model or detector succeeds, verify_adult_face must fail closed without guessing."""
    from safety.face_service import verify_adult_face

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp.write(b"fake_image_bytes")
        tmp_path = tmp.name

    try:
        mock_deepface = MagicMock()
        mock_deepface.extract_faces.return_value = [{"is_real": True}]
        # analyze raises an error (e.g. model unavailable / no face)
        mock_deepface.analyze.side_effect = RuntimeError("Face could not be detected")

        with patch.dict(os.environ, {"AI_SERVICE_URL": "", "GEMINI_API_KEY": "", "GOOGLE_API_KEY": ""}, clear=False):
            with patch.dict("sys.modules", {"deepface": MagicMock(DeepFace=mock_deepface)}):
                res = verify_adult_face(tmp_path)
                assert res.get("is_adult") is False
                assert res.get("estimated_age") is None
                assert res.get("reason") == "age_verification_unavailable"
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_verify_adult_face_passes_on_real_adult():
    """Real adult with age >= 18 and valid liveness passes."""
    from safety.face_service import verify_adult_face

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp.write(b"fake_image_bytes")
        tmp_path = tmp.name

    try:
        mock_deepface = MagicMock()
        mock_deepface.extract_faces.return_value = [{"is_real": True}]
        mock_deepface.analyze.return_value = [{"age": 28}]

        with patch.dict(os.environ, {"AI_SERVICE_URL": ""}, clear=False):
            with patch.dict("sys.modules", {"deepface": MagicMock(DeepFace=mock_deepface)}):
                res = verify_adult_face(tmp_path)
                assert res.get("is_adult") is True
                assert res.get("estimated_age") == 28
                assert res.get("method") == "DEEPFACE"
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_resend_sandbox_is_distinguishable_from_verified():
    """get_mail_status distinguishes sandbox from a verified domain."""
    from mailg.send_email import get_mail_status

    # Case 1: Unverified or default sandbox from address
    with patch.dict(os.environ, {
        "RESEND_API_KEY": "re_test_123",
        "RESEND_FROM_EMAIL": "onboarding@resend.dev",
    }, clear=True):
        status = get_mail_status()
        assert status["ok"] is True
        assert status["mail_mode"] == "resend_sandbox"
        assert status["is_production_ready"] is False

    # Case 2: Custom domain without RESEND_DOMAIN_VERIFIED=1
    with patch.dict(os.environ, {
        "RESEND_API_KEY": "re_test_123",
        "RESEND_FROM_EMAIL": "no-reply@devpluse.in",
        "RESEND_DOMAIN_VERIFIED": "0",
    }, clear=True):
        status = get_mail_status()
        assert status["ok"] is True
        assert status["mail_mode"] == "resend_sandbox"
        assert status["is_production_ready"] is False

    # Case 3: Verified custom production domain
    with patch.dict(os.environ, {
        "RESEND_API_KEY": "re_test_123",
        "RESEND_FROM_EMAIL": "safety@littlenet.safe",
        "RESEND_DOMAIN_VERIFIED": "1",
    }, clear=True):
        status = get_mail_status()
        assert status["ok"] is True
        assert status["mail_mode"] == "resend_verified"
        assert status["is_production_ready"] is True


def test_production_preflight_rejects_sandbox_only_mail():
    """Strict production preflight rejects sandbox mail mode."""
    from app import create_app
    app = create_app()

    # Test that readyz rejects sandbox in STRICT_PRODUCTION_PREFLIGHT mode
    with patch.dict(os.environ, {
        "RESEND_API_KEY": "re_test_123",
        "RESEND_FROM_EMAIL": "no-reply@devpluse.in",
        "RESEND_DOMAIN_VERIFIED": "0",
        "STRICT_PRODUCTION_PREFLIGHT": "1",
    }, clear=True):
        with app.test_client() as client:
            with patch("app.fetch_one", return_value={"ok": 1}):
                with patch("safety.remote_client.enabled", return_value=False):
                    resp = client.get("/readyz")
                    assert resp.status_code == 503
                    data = resp.get_json()
                    assert data["status"] == "degraded"
                    assert data["mail_mode"] == "resend_sandbox"

    # And passes when verified
    with patch.dict(os.environ, {
        "RESEND_API_KEY": "re_test_123",
        "RESEND_FROM_EMAIL": "safety@littlenet.safe",
        "RESEND_DOMAIN_VERIFIED": "1",
        "STRICT_PRODUCTION_PREFLIGHT": "1",
    }, clear=True):
        with app.test_client() as client:
            with patch("app.fetch_one", return_value={"ok": 1}):
                with patch("safety.remote_client.enabled", return_value=False):
                    resp = client.get("/readyz")
                    assert resp.status_code == 200
                    data = resp.get_json()
                    assert data["status"] == "ready"
                    assert data["mail_mode"] == "resend_verified"


def test_otp_send_failure_never_claims_code_sent():
    """When send_email returns False, begin_parent_registration reports email_sent=False."""
    from auth.parent_email_otp import begin_parent_registration

    with patch("auth.parent_email_otp._ensure_table"):
        with patch("auth.parent_email_otp._validate_registration", return_value=("testuser", "Test Parent", "parent@test.com", "Secret123!", "1980-01-01")):
            with patch("auth.parent_email_otp.get_db_connection") as mock_conn_fn:
                mock_conn = MagicMock()
                mock_cur = MagicMock()
                mock_conn.cursor.return_value.__enter__.return_value = mock_cur
                mock_conn_fn.return_value = mock_conn
                mock_cur.fetchone.side_effect = [None, {"user_id": 999}]

                with patch("auth.parent_email_otp._send_code", return_value=False):
                    res = begin_parent_registration({
                        "username": "testuser",
                        "full_name": "Test Parent",
                        "email": "parent@test.com",
                        "password": "SecretPassword123!",
                        "dob": "1980-01-01",
                        "guardian_declaration": "1",
                    })
                    assert res["email_sent"] is False
