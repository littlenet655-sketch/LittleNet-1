from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _text(path):
    return (ROOT / path).read_text(encoding='utf-8')


def test_parent_liveness_uses_real_mediapipe_blendshapes_and_self_hosted_module():
    template = _text('auth/templates/parent_liveness_verify.html')
    js = _text('static/js/parent_liveness_mediapipe.js')
    assert '/static/js/parent_liveness_mediapipe.js' in template
    assert '<script>' not in template
    assert '/static/vendor/mediapipe/vision_bundle.mjs' in js
    assert 'FaceLandmarker.createFromOptions' in js
    assert "runningMode: 'VIDEO'" in js
    assert 'outputFaceBlendshapes: true' in js
    assert "'eyeBlinkLeft'" in js and "'eyeBlinkRight'" in js
    assert "phase = 'WAIT_OPEN'" in js
    assert "phase = 'WAIT_CLOSED'" in js
    assert "phase = 'WAIT_REOPEN'" in js
    assert 'brightness' not in js.lower()


def test_mediapipe_build_assets_are_integrity_verified_not_just_hashed_after_download():
    installer = _text('tools/install_mediapipe_assets.py')
    assert 'PACKAGE_SHA256 = "ee318eaa3d42230aa10910d114faf2a488c577c4e4d33c7cb04126924aca505f"' in installer
    assert 'MODEL_SHA256 = "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"' in installer
    assert 'if actual != expected_sha256:' in installer
    assert 'SHA-256 mismatch' in installer
    assert 'registry.npmjs.org/@mediapipe/tasks-vision' in installer
    assert 'face_landmarker.task' in installer
    docker = _text('Dockerfile.web')
    modal = _text('modal_web.py')
    assert 'python tools/install_mediapipe_assets.py' in docker
    assert 'python tools/install_mediapipe_assets.py' in modal
    assert 'mediapipe_liveness_assets' in modal


def test_message_notes_only_select_active_parent_approved_friends():
    routes = _text('childMessage/routes.py')
    notes_start = routes.index('peers = fetch_all(')
    notes_end = routes.index('sample_notes =', notes_start)
    notes = routes[notes_start:notes_end]
    assert 'FROM followers f' in notes
    assert "f.approved=TRUE" in notes
    assert "f.approval_stage='ACTIVE'" in notes
    assert 'blocked_users' in notes
    assert 'muted_users' in notes
    assert "FROM users u\n        JOIN child_profiles" not in notes


def test_direct_media_route_reuses_canonical_social_visibility():
    app = _text('app.py')
    route_start = app.index("@app.route('/uploads/<path:filename>')")
    route_end = app.index("@app.route('/healthz')", route_start)
    route = app[route_start:route_end]
    assert 'post_visible_to' in route
    assert 'story_visible_to' in route
    assert 'can_interact' in route
    assert 'can_discover_child' in route
    assert "filename.startswith('profile_pictures/')" not in route
    signing = route.index("if stored.startswith('uploads/r2/')")
    assert route.index('post_visible_to') < signing
    assert route.index('can_interact') < signing
    assert route.index('can_discover_child') < signing


def test_friendship_trigger_cannot_promote_replayed_sender_approval():
    sql = _text('database/friendship_upgrade.sql')
    assert "ELSIF OLD.approval_stage='SENDER_PARENT_APPROVED'" in sql
    replay_guard = sql.index("ELSIF OLD.approval_stage='SENDER_PARENT_APPROVED'")
    tail = sql[replay_guard:]
    assert 'NEW.approved=FALSE' in tail or 'RETURN OLD' in tail or 'RETURN NEW' in tail
