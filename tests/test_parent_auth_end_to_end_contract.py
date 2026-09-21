"""End-to-end contract: parent auth on web is email-OTP-based (no face/liveness).

Parent face verification was removed by explicit product decision: the web
``/face-login/?mode=parent`` page, the ``/verify-parent-liveness/`` route, the
parent liveness template and its MediaPipe JS are all gone. Child Face ID
login (``mode=kids``) is untouched and must keep working.
"""
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


def test_parent_liveness_assets_are_removed():
    # The parent liveness page, its MediaPipe JS, and the route are deleted.
    assert not (ROOT / 'static/js/parent_liveness_mediapipe.js').exists()
    assert not (ROOT / 'auth/templates/parent_liveness_verify.html').exists()

    routes = (ROOT / 'auth/routes.py').read_text(encoding='utf-8')
    assert 'verify_parent_liveness_page' not in routes
    assert "verify-parent-liveness" not in routes
    assert 'parent_liveness_verify.html' not in routes
    assert 'parent_liveness_mediapipe' not in routes

    service = (ROOT / 'auth/service.py').read_text(encoding='utf-8')
    assert 'verify_adult_face' not in service

    # The shared face_service keeps verify_adult_face for non-parent AI
    # consumers (e.g. ai_server 18+ moderation); it just has no parent caller.
    face_service = (ROOT / 'safety/face_service.py').read_text(encoding='utf-8')
    assert 'def verify_adult_face' in face_service


def test_parent_face_id_login_is_removed_child_face_login_kept():
    routes = (ROOT / 'auth/routes.py').read_text(encoding='utf-8')
    login = (ROOT / 'auth/templates/login.html').read_text(encoding='utf-8')
    face_login = (ROOT / 'auth/templates/face_login.html').read_text(encoding='utf-8')

    # Parent Face ID login is gone: the route redirects parent mode to
    # password login, and no template offers it.
    assert "if mode == 'parent':" in routes
    assert "return redirect('/login/?mode=parent')" in routes
    assert "role = 'PARENT' if mode == 'parent' else 'CHILD'" not in routes
    assert 'Parent Face ID Login' not in login
    assert 'Parent Face ID Login' not in face_login
    assert "face_mode=='parent'" not in face_login
    assert 'Parent Email or Username' not in face_login
    assert '/face-login/?mode=parent' not in login

    # Child Face ID login is kept: kids link on the kids login page, kids
    # template copy, and the CHILD-role query in the route.
    assert '/face-login/?mode=kids' in login
    assert 'Face ID Login' in login
    assert "role='CHILD'" in routes
    assert 'Child Email or Username' in face_login
    assert 'Live Face ID Login' in face_login


def test_parent_activation_is_email_otp_only():
    routes = (ROOT / 'auth/routes.py').read_text(encoding='utf-8')
    otp = (ROOT / 'auth/parent_email_otp.py').read_text(encoding='utf-8')

    # Standalone registration: OTP success activates the account directly.
    assert "UPDATE users SET account_status='ACTIVE'" in routes
    assert "UPDATE users SET account_status='ACTIVE'" not in otp
    # Token guardian flow: OTP step route exists, selfie step does not.
    assert "@auth_bp.route('/verify-parent/<token>/otp/'" in routes
    assert 'ensure_token_parent_pending' in routes
    assert 'selfie_data' not in routes
    assert 'selfie_bytes' not in (ROOT / 'auth/service.py').read_text(encoding='utf-8')


def test_live_deploy_tracks_auth_changes():
    workflow = (ROOT / '.github/workflows/deploy-modal.yml').read_text(encoding='utf-8')
    for required_path in (
        "- 'auth/**'",
        "- 'mailg/**'",
        "- 'safety/face_service.py'",
    ):
        assert required_path in workflow
    # The deleted parent-liveness JS must not be an active tracked deploy path
    # (only a stale commented-out line may remain).
    active_lines = [ln for ln in workflow.splitlines() if not ln.strip().startswith('#')]
    assert not any('parent_liveness_mediapipe' in ln for ln in active_lines)
