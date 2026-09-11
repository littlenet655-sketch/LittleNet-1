from pathlib import Path
from unittest.mock import patch

import pytest

from app import app
from mobile.api import _issue_token


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as test_client:
        yield test_client


def _headers():
    token = _issue_token(
        {"user_id": 15, "role": "CHILD", "full_name": "Sai Gowda"}
    )
    return {"Authorization": f"Bearer {token}"}


def _user():
    return {
        "user_id": 15,
        "username": "saigowda",
        "full_name": "Sai Gowda",
        "email": None,
        "role": "CHILD",
        "age": 12,
        "account_status": "ACTIVE",
    }


def test_two_real_answers_drive_server_onboarding_transition(client):
    quizzes = {
        101: {"quiz_id": 101, "age_group": "12-13"},
        102: {"quiz_id": 102, "age_group": "12-13"},
    }
    attempted = set()

    def fetch(sql, params=()):
        if "FROM users WHERE user_id" in sql:
            return _user()
        if "FROM quizzes WHERE quiz_id" in sql:
            return quizzes.get(int(params[0]))
        raise AssertionError(sql)

    def record(child_id, quiz_id, answer):
        assert child_id == 15
        attempted.add(quiz_id)
        return True, answer, 10, "Saved by the server."

    with (
        patch("mobile.api.fetch_one", side_effect=fetch),
        patch("mobile.api.age_group", return_value="12-13"),
        patch("mobile.api.record_feed_answer", side_effect=record),
        patch("mobile.api.needs_onboarding_quiz", side_effect=lambda _: len(attempted) < 2),
        patch("mobile.api.feed_quiz_state", return_value={"required": False}),
    ):
        first = client.post(
            "/api/mobile/v1/kids/quiz/101/answer",
            headers=_headers(),
            json={"answer": "First safe answer"},
        )
        second = client.post(
            "/api/mobile/v1/kids/quiz/102/answer",
            headers=_headers(),
            json={"answer": "Second safe answer"},
        )

    assert first.status_code == 200
    assert first.get_json()["onboarding_complete"] is False
    assert attempted == {101, 102}
    assert second.status_code == 200
    assert second.get_json()["onboarding_complete"] is True


def test_fake_or_wrong_age_quiz_id_is_rejected_without_recording(client):
    def fetch(sql, params=()):
        if "FROM users WHERE user_id" in sql:
            return _user()
        if "FROM quizzes WHERE quiz_id" in sql:
            return None
        raise AssertionError(sql)

    with (
        patch("mobile.api.fetch_one", side_effect=fetch),
        patch("mobile.api.age_group", return_value="12-13"),
        patch("mobile.api.record_feed_answer") as record,
    ):
        response = client.post(
            "/api/mobile/v1/kids/quiz/99901/answer",
            headers=_headers(),
            json={"answer": "Client fallback answer"},
        )

    assert response.status_code == 404
    assert response.get_json()["error"] == "quiz_not_available"
    record.assert_not_called()


def test_onboarding_seed_covers_every_supported_age_band_with_real_rows():
    root = Path(__file__).resolve().parents[1]
    migration = (
        root / "db/migrations/20260911153000_seed_onboarding_safety_quizzes.sql"
    ).read_text(encoding="utf-8")
    mobile_api = (root / "mobile/api.py").read_text(encoding="utf-8")
    flutter_quiz = (
        root / "mobile_flutter/lib/features/quiz/quiz_screen.dart"
    ).read_text(encoding="utf-8")
    service = (root / "quiz/service.py").read_text(encoding="utf-8")

    for age_group in ("6-8", "9-11", "12-13", "14-18"):
        assert f"('{age_group}')" in migration
    assert "ON CONFLICT (question, age_group) DO NOTHING" in migration
    assert "99901" not in mobile_api
    assert "99901" not in flutter_quiz
    assert "COUNT(DISTINCT quiz_id)" in service
