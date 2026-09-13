"""Contract tests for the minimal GET /api/mobile/v1/me onboarding addition.

CHILD responses must carry authoritative gate state computed with the exact
Agent A Facenet512 enrollment check. PARENT/ADMIN responses omit onboarding.
"""
from unittest.mock import patch

import pytest
from app import app
from mobile.api import _issue_token


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def _headers(user_id, role):
    token = _issue_token({"user_id": user_id, "role": role, "full_name": "Test User"})
    return {"Authorization": f"Bearer {token}"}


def _user_row(user_id, role):
    return {
        "user_id": user_id,
        "username": "test_user",
        "full_name": "Test User",
        "email": "test@example.com",
        "role": role,
        "age": 10 if role == "CHILD" else 35,
        "account_status": "ACTIVE",
    }


def _fetch_one(user_id, role, face_row):
    def side_effect(query, params=None):
        if "FROM users" in query:
            return _user_row(user_id, role)
        if "face_profiles" in query:
            return face_row
        return None

    return side_effect


def _child_context(user_id=202, face_row=None, quiz_required=False, onboarding_quiz=False):
    return (
        patch("mobile.api.fetch_one", side_effect=_fetch_one(user_id, "CHILD", face_row)),
        patch("mobile.api.get_child_profile", return_value={"child_id": user_id}),
        patch("mobile.api.feed_quiz_state", return_value={"required": quiz_required, "posts_seen": 0, "interval": 4}),
        patch("mobile.api.needs_onboarding_quiz", return_value=onboarding_quiz),
    )


def _valid_face():
    return {"embedding": [0.1] * 512, "model_name": "Facenet512"}


def test_me_unauthenticated(client):
    res = client.get("/api/mobile/v1/me")
    assert res.status_code == 401
    assert res.get_json()["error"] == "mobile_auth_required"


def test_me_child_enrolled_no_quiz_gates_clear(client):
    patches = _child_context(face_row=_valid_face())
    with patches[0], patches[1], patches[2], patches[3]:
        res = client.get("/api/mobile/v1/me", headers=_headers(202, "CHILD"))
    assert res.status_code == 200
    payload = res.get_json()
    assert payload["ok"] is True
    assert payload["onboarding"] == {"face_required": False, "quiz_required": False}


def test_me_child_missing_face_profile_requires_face(client):
    patches = _child_context(face_row=None)
    with patches[0], patches[1], patches[2], patches[3]:
        res = client.get("/api/mobile/v1/me", headers=_headers(202, "CHILD"))
    assert res.status_code == 200
    assert res.get_json()["onboarding"] == {"face_required": True, "quiz_required": False}


def test_me_child_invalid_embedding_fails_closed(client):
    patches = _child_context(face_row={"embedding": [0.0] * 512, "model_name": "Facenet512"})
    with patches[0], patches[1], patches[2], patches[3]:
        res = client.get("/api/mobile/v1/me", headers=_headers(202, "CHILD"))
    assert res.status_code == 200
    assert res.get_json()["onboarding"]["face_required"] is True


def test_me_child_wrong_model_requires_face(client):
    patches = _child_context(face_row={"embedding": [0.1] * 512, "model_name": "LocalBiometricV1"})
    with patches[0], patches[1], patches[2], patches[3]:
        res = client.get("/api/mobile/v1/me", headers=_headers(202, "CHILD"))
    assert res.status_code == 200
    assert res.get_json()["onboarding"]["face_required"] is True


def test_me_child_enrolled_with_onboarding_quiz(client):
    patches = _child_context(face_row=_valid_face(), onboarding_quiz=True)
    with patches[0], patches[1], patches[2], patches[3]:
        res = client.get("/api/mobile/v1/me", headers=_headers(202, "CHILD"))
    assert res.status_code == 200
    assert res.get_json()["onboarding"] == {"face_required": False, "quiz_required": True}


def test_me_parent_omits_onboarding(client):
    with patch("mobile.api.fetch_one", side_effect=_fetch_one(101, "PARENT", None)), \
         patch("mobile.api.get_child_profile", return_value=None), \
         patch("mobile.api.feed_quiz_state", return_value={}), \
         patch("mobile.api.needs_onboarding_quiz", return_value=False):
        res = client.get("/api/mobile/v1/me", headers=_headers(101, "PARENT"))
    assert res.status_code == 200
    assert "onboarding" not in res.get_json()


def test_me_admin_omits_onboarding(client):
    with patch("mobile.api.fetch_one", side_effect=_fetch_one(1, "ADMIN", None)), \
         patch("mobile.api.get_child_profile", return_value=None), \
         patch("mobile.api.feed_quiz_state", return_value={}), \
         patch("mobile.api.needs_onboarding_quiz", return_value=False):
        res = client.get("/api/mobile/v1/me", headers=_headers(1, "ADMIN"))
    assert res.status_code == 200
    assert "onboarding" not in res.get_json()
