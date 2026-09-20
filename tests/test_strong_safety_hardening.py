from safety.chat_context import contextual_chat_risk
from safety.face_service import _face_match_threshold
from safety.policy import decide, policy_metadata
from safety.text_service import _normalized_text, check_text


def test_spaced_letter_sexual_evasion_is_normalized_and_blocked(monkeypatch):
    monkeypatch.setattr("safety.text_service._detox_scores", lambda _text: {"sexual_explicit": 0.0})
    assert "sendnudes" in _normalized_text("s e n d  n u d e s")
    signals = check_text("s e n d  n u d e s")
    assert decide(signals).action == "BLOCK"


def test_self_harm_and_dangerous_challenge_phrases_are_hard_blocked(monkeypatch):
    monkeypatch.setattr("safety.text_service._detox_scores", lambda _text: {"sexual_explicit": 0.0})
    for text, category in (
        ("I want to end my life", "SELF_HARM"),
        ("Try the blackout challenge", "DANGEROUS_CHALLENGE"),
    ):
        signals = check_text(text)
        assert signals["category"] == category
        assert decide(signals).action == "BLOCK"


def test_multi_turn_grooming_requires_distinct_cue_families():
    history = [
        {"sender_child_id": 1, "message_text": "Keep this a secret"},
        {"sender_child_id": 2, "message_text": "Okay"},
    ]
    result = contextual_chat_risk(history, "Send me a selfie")
    assert result["suspicious"] is True
    assert result["cue_families"] == ["photo_request", "secrecy"]

    benign = contextual_chat_risk(
        [{"sender_child_id": 1, "message_text": "My science project is secret until Friday"}],
        "That sounds fun",
    )
    assert benign["suspicious"] is False


def test_face_threshold_defaults_and_cannot_be_weakened(monkeypatch):
    monkeypatch.delenv("LITTLENET_FACE_MATCH_MAX_DISTANCE", raising=False)
    assert _face_match_threshold() == 0.35
    monkeypatch.setenv("LITTLENET_FACE_MATCH_MAX_DISTANCE", "0.50")
    assert _face_match_threshold() == 0.35
    monkeypatch.setenv("LITTLENET_FACE_MATCH_MAX_DISTANCE", "0.30")
    assert _face_match_threshold() == 0.30


def test_policy_provenance_is_versioned():
    assert policy_metadata() == {
        "policy_name": "littlenet-college-child-safety",
        "policy_version": 1,
    }
