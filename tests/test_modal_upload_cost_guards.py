import io
import os
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch


def test_deterministic_text_gate_catches_obvious_sexual_request_without_ml():
    from safety.policy import decide
    from safety.text_service import check_text_deterministic

    signals = check_text_deterministic("send me nudes")
    decision = decide(signals, "STRICT", 0.40)

    assert signals["deterministic_sexual"] is True
    assert decision.action == "BLOCK"


def test_deterministic_text_gate_leaves_normal_caption_for_full_pipeline():
    from safety.policy import decide
    from safety.text_service import check_text_deterministic

    signals = check_text_deterministic("My science fair project")
    decision = decide(signals, "STRICT", 0.40)

    assert signals["deterministic_only"] is True
    assert signals["adult_score"] == 0.0
    assert decision.action == "ALLOW"


def test_moderation_cache_never_stores_partial_or_total_failures():
    from services import moderation_cache as cache

    with patch.object(cache, "execute") as execute:
        assert cache.store_cached_signals(
            "IMAGE",
            "a" * 64,
            {"total_safety_failure": True, "adult_score": 0.0},
        ) is False
        assert cache.store_cached_signals(
            "IMAGE",
            "b" * 64,
            {"partial_safety_failure": True, "adult_score": 0.0},
        ) is False
        execute.assert_not_called()


def test_moderation_cache_hit_is_versioned_and_counted(monkeypatch):
    from services import moderation_cache as cache

    monkeypatch.setenv("LITTLENET_MODERATION_CACHE_VERSION", "test-v1")
    row = {
        "signals": {
            "adult_score": 0.01,
            "violence_score": 0.0,
            "weapon_score": 0.0,
            "toxicity_score": 0.0,
            "total_safety_failure": False,
            "partial_safety_failure": False,
        }
    }
    with patch.object(cache, "fetch_one", return_value=row), patch.object(cache, "execute") as execute:
        result = cache.get_cached_signals("IMAGE", "c" * 64)

    assert result is not None
    assert result["cache"]["hit"] is True
    assert result["cache"]["version"] == "test-v1"
    execute.assert_called_once()


def test_image_cpu_cost_guard_defaults_off_outside_modal(monkeypatch):
    from services import modal_image_moderation as client

    monkeypatch.delenv("LITTLENET_USE_MODAL_IMAGE_CPU", raising=False)
    monkeypatch.delenv("LITTLENET_ALLOW_IMAGE_GPU_FALLBACK", raising=False)
    assert client.enabled() is False
    assert client.allow_gpu_fallback() is False

    monkeypatch.setenv("LITTLENET_USE_MODAL_IMAGE_CPU", "1")
    assert client.enabled() is True


def test_ai_server_bundles_caption_and_image_in_one_request(monkeypatch):
    import ai_server

    monkeypatch.setenv("AI_SHARED_SECRET", "unit-test-secret")
    monkeypatch.setattr(
        ai_server,
        "check_text",
        lambda text: {"category": "TEXT", "toxicity_score": 0.01, "total_safety_failure": False},
    )
    monkeypatch.setattr(
        ai_server,
        "check_image",
        lambda path: {"category": "IMAGE", "adult_score": 0.02, "total_safety_failure": False},
    )

    response = ai_server.app.test_client().post(
        "/ai/moderate-upload",
        data={
            "content_type": "IMAGE",
            "text": "hello",
            "file": (io.BytesIO(b"fake-image-bytes"), "x.jpg"),
        },
        headers={"X-LittleNet-AI-Key": "unit-test-secret"},
        content_type="multipart/form-data",
    )

    assert response.status_code == 200
    payload = response.get_json()
    assert payload["ok"] is True
    assert payload["text_signals"]["category"] == "TEXT"
    assert payload["media_signals"]["category"] == "IMAGE"


def test_remote_upload_bundle_uses_single_http_post(monkeypatch):
    from safety import remote_client

    monkeypatch.setenv("AI_SERVICE_URL", "https://ai.example")
    monkeypatch.setenv("AI_SHARED_SECRET", "secret")

    fake_response = Mock()
    fake_response.raise_for_status.return_value = None
    fake_response.json.return_value = {
        "ok": True,
        "text_signals": {"category": "TEXT"},
        "media_signals": {"category": "IMAGE", "adult_score": 0.0},
    }

    fd, path = tempfile.mkstemp(suffix=".jpg")
    os.close(fd)
    Path(path).write_bytes(b"x")
    try:
        with patch.object(remote_client.requests, "post", return_value=fake_response) as post:
            result = remote_client.moderate_upload("IMAGE", path, "caption")

        assert result["media_signals"]["category"] == "IMAGE"
        assert post.call_count == 1
        assert post.call_args.args[0] == "https://ai.example/ai/moderate-upload"
    finally:
        Path(path).unlink(missing_ok=True)
