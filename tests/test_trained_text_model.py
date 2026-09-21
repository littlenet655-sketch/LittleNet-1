import json
from pathlib import Path
from unittest.mock import patch


def _metadata():
    return {
        "labels": ["nudity", "violence", "cyberbullying", "gambling"],
        "thresholds": {
            "nudity": 0.80,
            "violence": 0.70,
            "cyberbullying": 0.60,
            "gambling": 0.75,
        },
        "signal_map": {},
        "release": "unit-text-v2",
    }


def test_trained_text_mode_defaults_off_and_accepts_shadow_enforce(monkeypatch):
    from safety import littlenet_trained_text as trained

    monkeypatch.delenv("LITTLENET_TRAINED_TEXT_MODE", raising=False)
    assert trained.mode() == "off"

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "shadow")
    assert trained.mode() == "shadow"

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "enforce")
    assert trained.mode() == "enforce"

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "unexpected")
    assert trained.mode() == "off"


def test_trained_text_bundle_availability_requires_complete_private_bundle(tmp_path, monkeypatch):
    from safety import littlenet_trained_text as trained

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_PATH", str(tmp_path))
    assert trained.available() is False

    (tmp_path / "config.json").write_text("{}", encoding="utf-8")
    (tmp_path / "littlenet_metadata.json").write_text(
        json.dumps(
            {
                "format": "huggingface_sequence_classification",
                "release": "unit",
                "labels": ["safe", "unsafe"],
                "thresholds": {"safe": 0.5, "unsafe": 0.5},
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "model.safetensors").write_bytes(b"weights")
    assert trained.available() is False

    (tmp_path / "vocab.txt").write_text("[PAD]\n[UNK]\n", encoding="utf-8")
    assert trained.available() is True


def test_trained_text_signal_mapping_respects_per_label_thresholds():
    from safety import littlenet_trained_text as trained

    signals = trained._signals_from_scores(
        {
            "nudity": 0.79,          # below tuned threshold: must not hard block
            "violence": 0.82,        # above threshold
            "cyberbullying": 0.91,   # above threshold
            "gambling": 0.74,        # below threshold
        },
        _metadata(),
    )

    assert signals["adult_score"] == 0.0
    # Model-space thresholds are translated to policy-space REVIEW risk.
    assert signals["violence_score"] == 0.50
    assert signals["toxicity_score"] == 0.50
    assert signals["general_score"] == 0.50
    triggered = signals["model_signals"]["littlenet_trained_text"]["triggered"]
    assert triggered == {
        "nudity": False,
        "violence": True,
        "cyberbullying": True,
        "gambling": False,
    }
    states = signals["model_signals"]["littlenet_trained_text"]["states"]
    assert states["violence"] == "review"
    assert states["cyberbullying"] == "review"


def test_safe_label_never_becomes_policy_risk():
    from safety import littlenet_trained_text as trained

    metadata = {
        "labels": ["safe", "sexual"],
        "review_thresholds": {"safe": 0.50, "sexual": 0.80},
        "block_thresholds": {},
        "signal_map": {},
        "release": "unit",
        "format": "test",
    }
    signals = trained._signals_from_scores({"safe": 0.99, "sexual": 0.10}, metadata)
    assert signals["general_score"] == 0.0
    assert signals["adult_score"] == 0.0


def test_custom_v2_layout_is_recognized_without_loading_torch(tmp_path, monkeypatch):
    from safety import littlenet_trained_text as trained

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_PATH", str(tmp_path))
    (tmp_path / "metadata.json").write_text(
        json.dumps({"labels": [
            "sexual", "grooming", "bullying", "hate", "violence", "self_harm",
            "drugs", "alcohol", "smoking", "gambling", "profanity",
            "pii_request", "contact_request",
        ]}),
        encoding="utf-8",
    )
    (tmp_path / "littlenet_text_model.pt").write_bytes(b"checkpoint")
    (tmp_path / "vocab.txt").write_text("[PAD]\n[UNK]\n", encoding="utf-8")
    encoder = tmp_path / "encoder"
    encoder.mkdir()
    (encoder / "config.json").write_text("{}", encoding="utf-8")

    assert trained.available() is True
    metadata = trained._load_metadata()
    assert metadata["format"] == "littlenet_v2_custom_distilbert"
    assert metadata["max_length"] == 128
    assert len(metadata["labels"]) == 13


def test_shadow_mode_cannot_change_current_text_decision(monkeypatch):
    from safety import littlenet_trained_text as trained
    from safety import text_service

    monkeypatch.setenv("LITTLENET_AI_SERVER", "1")
    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "shadow")
    monkeypatch.delenv("LITTLENET_ENABLE_TEXT_CLASSIFIER", raising=False)

    trained_result = {
        "adult_score": 0.99,
        "sexual_score": 0.99,
        "violence_score": 0.99,
        "weapon_score": 0.0,
        "toxicity_score": 0.99,
        "general_score": 0.99,
        "category": "SEXUAL_LANGUAGE",
        "total_safety_failure": False,
        "partial_safety_failure": False,
        "model_signals": {
            "littlenet_trained_text": {
                "release": "unit-text-v2",
                "probabilities": {"nudity": 0.99},
                "thresholds": {"nudity": 0.80},
                "triggered": {"nudity": True},
            }
        },
        "trained_text_release": "unit-text-v2",
    }

    with patch("safety.remote_client.enabled", return_value=False), \
         patch.object(text_service, "_detox_scores", return_value={"toxicity": 0.01, "sexual_explicit": 0.01}), \
         patch.object(trained, "available", return_value=True), \
         patch.object(trained, "predict", return_value=trained_result):
        result = text_service.check_text("My science fair project")

    assert result["adult_score"] == 0.01
    assert result["toxicity_score"] == 0.01
    assert result["category"] == "TEXT"
    assert result["partial_safety_failure"] is False
    assert result["trained_text_shadow"]["release"] == "unit-text-v2"


def test_enforce_mode_merges_trained_evidence_into_existing_policy(monkeypatch):
    from safety import littlenet_trained_text as trained
    from safety import text_service
    from safety.policy import decide

    monkeypatch.setenv("LITTLENET_AI_SERVER", "1")
    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "enforce")
    monkeypatch.delenv("LITTLENET_ENABLE_TEXT_CLASSIFIER", raising=False)

    trained_result = {
        "adult_score": 0.95,
        "sexual_score": 0.95,
        "violence_score": 0.0,
        "weapon_score": 0.0,
        "toxicity_score": 0.0,
        "general_score": 0.95,
        "category": "SEXUAL_LANGUAGE",
        "total_safety_failure": False,
        "partial_safety_failure": False,
        "model_signals": {"littlenet_trained_text": {"release": "unit-text-v2"}},
        "trained_text_release": "unit-text-v2",
    }

    with patch("safety.remote_client.enabled", return_value=False), \
         patch.object(text_service, "_detox_scores", return_value={"toxicity": 0.01, "sexual_explicit": 0.01}), \
         patch.object(trained, "available", return_value=True), \
         patch.object(trained, "predict", return_value=trained_result):
        result = text_service.check_text("ambiguous test sentence")

    assert result["adult_score"] == 0.95
    assert result["trained_text_release"] == "unit-text-v2"
    assert decide(result, "STRICT").action == "BLOCK"


def test_enforce_mode_missing_bundle_fails_to_review_not_allow(monkeypatch):
    from safety import littlenet_trained_text as trained
    from safety import text_service
    from safety.policy import decide

    monkeypatch.setenv("LITTLENET_AI_SERVER", "1")
    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "enforce")
    monkeypatch.delenv("LITTLENET_ENABLE_TEXT_CLASSIFIER", raising=False)

    with patch("safety.remote_client.enabled", return_value=False), \
         patch.object(text_service, "_detox_scores", return_value={"toxicity": 0.01, "sexual_explicit": 0.01}), \
         patch.object(trained, "available", return_value=False):
        result = text_service.check_text("ordinary text")

    assert result["total_safety_failure"] is False
    assert result["partial_safety_failure"] is True
    assert "trained_text_unavailable" in result["errors"]
    assert decide(result, "STRICT").action == "REVIEW"


def test_cache_version_is_unchanged_off_or_shadow_and_isolated_on_enforce(monkeypatch):
    from services import moderation_cache

    monkeypatch.setenv("LITTLENET_MODERATION_CACHE_VERSION", "base-v1")
    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_RELEASE", "text-v2")

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "off")
    assert moderation_cache.cache_version() == "base-v1"

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "shadow")
    assert moderation_cache.cache_version() == "base-v1"

    monkeypatch.setenv("LITTLENET_TRAINED_TEXT_MODE", "enforce")
    assert moderation_cache.cache_version() == "base-v1|text:text-v2"


def test_modal_deployment_keeps_trained_text_off_until_explicit_promotion():
    root = Path(__file__).resolve().parents[1]
    ai = (root / "modal_ai.py").read_text(encoding="utf-8")
    web = (root / "modal_web.py").read_text(encoding="utf-8")

    assert '"LITTLENET_TRAINED_TEXT_MODE": "off"' in ai
    assert '"LITTLENET_TRAINED_TEXT_MODE": "off"' in web
    assert "--trained-text-preflight-only" in ai
