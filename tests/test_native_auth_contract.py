from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_native_parent_signup_sends_all_backend_required_fields():
    auth = _text("mobile_flutter/lib/screens/auth.dart")
    for token in (
        "'username': username.text.trim()",
        "'full_name': fullName.text.trim()",
        "'email': email.text.trim()",
        "'password': password.text",
        "'dob': dob.text",
        "'guardian_declaration': '1'",
    ):
        assert token in auth
    assert "showDatePicker" in auth
    assert "guardianDeclaration" in auth


def test_native_parent_email_flow_surfaces_delivery_and_resend_state():
    auth = _text("mobile_flutter/lib/screens/auth.dart")
    assert "initialEmailSent: data['email_sent'] == true" in auth
    assert "Future<void> _resendOtp()" in auth
    assert "/api/mobile/v1/auth/parent/resend-email" in auth
    assert "Verification email sent." in auth
    assert "verification email was not delivered" in auth


def test_mobile_parent_verification_is_email_then_live_camera():
    api = _text("mobile/api.py")
    assert "/api/mobile/v1/auth/parent/register" in api
    assert "/api/mobile/v1/auth/parent/verify-email" in api
    assert "/api/mobile/v1/auth/parent/resend-email" in api
    assert "/api/mobile/v1/auth/parent/verify-liveness" in api
    assert "verify_parent_email_otp" in api
    assert "verify_adult_face" in api
    assert "email_verification_required" in api


def test_native_face_login_uses_front_camera_and_real_face_service():
    auth = _text("mobile_flutter/lib/screens/auth.dart")
    api = _text("mobile/api.py")
    assert "preferredCameraDevice: CameraDevice.front" in auth
    assert "widget.api.faceLogin" in auth
    assert "/api/mobile/v1/auth/face-login" in api
    assert "ok, reason, _ = verify(user[\"user_id\"], path)" in api


def test_email_otp_resend_error_path_has_os_import_and_no_sandbox_claim():
    otp = _text("auth/parent_email_otp.py")
    assert "import os" in otp
    assert "Check the verified Resend sender/domain configuration" in otp
    assert "testing mode" not in otp


def test_demo_database_reset_is_explicit_and_preserves_learning_bank():
    reset = _text("tools/reset_demo_accounts.py")
    assert 'CONFIRMATION = "RESET_ALL_ACCOUNTS"' in reset
    assert "TRUNCATE TABLE users RESTART IDENTITY CASCADE" in reset
    assert '"quizzes"' in reset
    assert '"learning_challenges"' in reset
    assert "DATABASE_URL is not configured" in reset
    modal = _text("modal_reset_demo.py")
    assert "littlenet-web-secrets" in modal
    assert "reset_all_accounts" in modal
    assert "dry_run: bool = True" in modal


def test_v2_parent_signup_and_branding_contract():
    signup = _text("mobile_flutter/lib/features/auth/parent_signup_screen.dart")
    login = _text("mobile_flutter/lib/features/auth/login_screen.dart")

    # Parent registration must include username in state and post body
    assert "_usernameController" in signup
    assert "'username': _usernameController.text.trim()" in signup
    assert "Icons.alternate_email" in signup
    assert "Choose a unique username" in signup

    # Login screen must use LittleNetAppLogo and no generic shield icon
    assert "LittleNetAppLogo" in login
    assert "Icons.shield_outlined" not in login

