from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_parent_otp_is_never_exposed_by_default_or_in_production():
    config = source("config.py")
    otp = source("auth/parent_email_otp.py")
    assert 'os.getenv("ENABLE_DEV_OTP", "0")' in config
    assert "ENABLE_DEV_OTP must never be enabled in production" in config
    assert "Config.ENABLE_DEV_OTP and not Config._PRODUCTION" in otp
    assert "os.getenv('ENABLE_DEV_OTP', '1')" not in otp


def test_release_client_does_not_consume_server_returned_otp():
    screen = source("mobile_app/src/screens/ParentOnboarding.tsx")
    assert "devCode: __DEV__ ? response.dev_code : undefined" in screen
    assert "if (__DEV__ && response.dev_code)" in screen


def test_guardian_certification_requires_affirmative_action():
    screen = source("mobile_app/src/screens/ParentOnboarding.tsx")
    assert "useState(false)" in screen
    assert "if (!guardianAgreed)" in screen
