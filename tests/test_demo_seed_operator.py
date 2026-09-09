from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_demo_seed_requires_private_password_and_has_no_public_password():
    helper = (ROOT / "modal_demo.py").read_text(encoding="utf-8")
    seeder = (ROOT / "tools/seed_demo_accounts.py").read_text(encoding="utf-8")

    assert "LITTLENET_DEMO_PASSWORD" in helper
    assert "LITTLENET_ENABLE_DEMO_SEED" in helper
    assert "LITTLENET_DEMO_PASSWORD" in seeder
    assert "LITTLENET_ENABLE_DEMO_SEED" in seeder
    assert "StudentAIT2026!" not in helper
    assert "ParentAIT2026!" not in helper
    assert "Password123!" not in helper


def test_demo_seed_targets_expected_college_demo_identities():
    helper = (ROOT / "modal_demo.py").read_text(encoding="utf-8")
    assert '"kid": "ait_star_student"' in helper
    assert '"parent": "mentor_parent@ait.edu"' in helper
    assert '"admin": "admin@littlenet.com"' in helper
