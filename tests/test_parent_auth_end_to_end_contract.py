from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_parent_registration_has_no_arithmetic_guardian_challenge():
    template = (ROOT / 'auth/templates/parent_register_direct.html').read_text(encoding='utf-8')
    otp = (ROOT / 'auth/parent_email_otp.py').read_text(encoding='utf-8')
    routes = (ROOT / 'auth/routes.py').read_text(encoding='utf-8')

    assert 'Guardian Verification Challenge' not in template
    assert 'adult_challenge_expected' not in template
    assert 'adult_challenge_answer' not in template
    assert 'adult_challenge_expected' not in otp
    assert 'adult_challenge_answer' not in otp
    assert 'challenge_q=' not in routes
    assert 'challenge_expected=' not in routes


def test_parent_liveness_is_adaptive_and_cache_busted():
    js = (ROOT / 'static/js/parent_liveness_mediapipe.js').read_text(encoding='utf-8')
    template = (ROOT / 'auth/templates/parent_liveness_verify.html').read_text(encoding='utf-8')

    assert 'eyeAspectRatio' in js
    assert 'openEarBaseline' in js
    assert 'CALIBRATION_FRAMES' in js
    assert 'MAX_TRANSIENT_ERRORS' in js
    assert 'adaptive-blink-' in template
    assert 'COMPLETE A LIVE BLINK FIRST' in js


def test_parent_face_id_is_enrolled_and_can_log_in():
    routes = (ROOT / 'auth/routes.py').read_text(encoding='utf-8')
    login = (ROOT / 'auth/templates/login.html').read_text(encoding='utf-8')
    face_login = (ROOT / 'auth/templates/face_login.html').read_text(encoding='utf-8')

    assert "enroll(parent['user_id'], path)" in routes
    assert "role = 'PARENT' if mode == 'parent' else 'CHILD'" in routes
    assert "role=%s AND account_status='ACTIVE'" in routes
    assert 'Parent Face ID Login' in login
    assert '/face-login/?mode=' in login
    assert "face_mode=='parent'" in face_login
    assert 'Parent Email or Username' in face_login


def test_live_deploy_tracks_auth_and_liveness_changes():
    workflow = (ROOT / '.github/workflows/deploy-modal.yml').read_text(encoding='utf-8')
    for required_path in (
        "- 'auth/**'",
        "- 'mailg/**'",
        "- 'static/js/parent_liveness_mediapipe.js'",
        "- 'safety/face_service.py'",
    ):
        assert required_path in workflow
