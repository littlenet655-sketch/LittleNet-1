from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_modal_preflight_covers_full_live_stack():
    src = (ROOT / 'modal_web.py').read_text(encoding='utf-8')
    for required in (
        "to_regclass('public.posts')",
        "to_regclass('public.comments')",
        "SELECT COUNT(*)::int n FROM quizzes",
        '_smtp_healthcheck()',
        'r2_healthcheck()',
        'public_base_url',
        'ai.get("ok")',
    ):
        assert required in src


def test_deploy_workflow_runs_runtime_gates_then_builds_native_flutter_apk():
    workflow = (ROOT / '.github/workflows/deploy-modal.yml').read_text(encoding='utf-8')
    required_order = [
        'modal deploy modal_ai.py',
        'modal deploy modal_web.py',
        'modal run modal_web.py --init-db',
        'modal run modal_web.py --seed',
        # Warm the GPU service before strict preflight so a legitimate cold start
        # cannot make the web dependency check fail before model validation runs.
        'modal run modal_ai.py',
        'modal run modal_web.py --preflight',
        '/readyz',
        "E2E_REQUIRE_READY: '1'",
        'Generate exact-branded native Android runner',
        'flutter build apk --release',
    ]
    positions = [workflow.index(token) for token in required_order]
    assert positions == sorted(positions)
    assert 'LITTLENET_API_BASE' in workflow
    assert 'LittleNet-live-native-Flutter-APK' in workflow
    assert "package: name='com.littlenet.app'" in workflow
    assert 'lib/arm64-v8a/libflutter.so' in workflow
    assert 'WebView dependency/code found in live native app' in workflow


def test_live_browser_smoke_can_fail_closed_on_degraded_readyz():
    spec = (ROOT / 'tests/e2e/release-smoke.spec.js').read_text(encoding='utf-8')
    assert 'E2E_REQUIRE_READY' in spec
    assert "expect(response.status()).toBe(200)" in spec
    assert "expect(body.status).toBe('ready')" in spec


def test_r2_release_healthcheck_is_read_only():
    src = (ROOT / 'services/object_storage.py').read_text(encoding='utf-8')
    health = src[src.index('def healthcheck()'):src.index('def is_reference')]
    assert 'head_bucket' in health
    assert 'upload_file' not in health
    assert 'delete_object' not in health
