from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_guardian_verification_requires_explicit_express_mode_or_local_mock_gate():
    src = (ROOT / "auth/service.py").read_text(encoding="utf-8")
    assert 'form_data.get("verification_mode") == "EXPRESS"' in src
    assert 'LITTLENET_ALLOW_MOCK_IDENTITY' in src
    assert '"localhost" in base_url or "127.0.0.1" in base_url' in src
    assert 'and not base_url.startswith("https://")' in src
    assert 'or (not selfie_bytes and not doc_number and consent)' not in src


def test_adult_face_gate_never_defaults_missing_result_to_success():
    src = (ROOT / "auth/service.py").read_text(encoding="utf-8")
    assert "adult_res.get('is_adult') is not True" in src
    assert "adult_res.get('is_adult', True)" not in src
    assert 'datetime.strptime(dob, "%Y-%m-%d")' in src
    assert 'birth_year > 2006' not in src


def test_legacy_token_only_child_approval_is_disabled():
    routes = (ROOT / "auth/routes.py").read_text(encoding="utf-8")
    service = (ROOT / "auth/service.py").read_text(encoding="utf-8")
    start = routes.index("@auth_bp.route('/approve/<token>/'")
    end = routes.index("@auth_bp.route('/register-parent'", start)
    legacy = routes[start:end]
    assert "redirect(f'/verify-parent/{token}/', code=303)" in legacy
    assert 'approve_child_account(token)' not in legacy
    helper = service[service.index('def approve_child_account(token):'):service.index('def login_user(', service.index('def approve_child_account(token):'))]
    assert 'raise RuntimeError' in helper
    assert "UPDATE users SET account_status='ACTIVE'" not in helper


def test_parent_approval_details_fail_closed_without_verified_record():
    src = (ROOT / "auth/service.py").read_text(encoding="utf-8")
    assert 'PARENT_VERIFICATION_REQUIRED' in src
    assert 'if not ver_row or ver_row.get("verification_status") != "VERIFIED"' in src
