"""Contract tests for the parent face-enrollment deferral flow.

Release-blocker context: the child's "Skip for Now" button
(POST /api/mobile/v1/kids/face/skip) was a permanent dead end (403) because
no API existed for a parent to approve the deferral, and nothing ever set
child_profiles.face_enrollment_skipped=TRUE. This suite covers the new
parent decision endpoint and the skip endpoint's approved/unapproved paths.
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


def _parent_headers(user_id=101):
    token = _issue_token({"user_id": user_id, "role": "PARENT", "account_status": "ACTIVE"})
    return {"Authorization": f"Bearer {token}"}


def _child_headers(user_id=202):
    token = _issue_token({"user_id": user_id, "role": "CHILD", "account_status": "ACTIVE"})
    return {"Authorization": f"Bearer {token}"}


_PARENT_ROW = {"user_id": 101, "role": "PARENT", "account_status": "ACTIVE"}
_CHILD_ROW = {"user_id": 202, "role": "CHILD", "account_status": "ACTIVE"}


def test_face_deferral_unauthenticated(client):
    res = client.post("/api/mobile/v1/parent/children/202/face/deferral", json={"action": "approve"})
    assert res.status_code == 401
    assert res.get_json()["error"] == "mobile_auth_required"


def test_face_deferral_non_parent_rejected(client):
    headers = _child_headers(202)
    with patch("mobile.api.fetch_one", return_value=_CHILD_ROW):
        res = client.post("/api/mobile/v1/parent/children/202/face/deferral", headers=headers, json={"action": "approve"})
        assert res.status_code == 403
        assert res.get_json()["error"] == "role_forbidden"


def test_face_deferral_not_owned_child_rejected(client):
    headers = _parent_headers(101)
    with patch("mobile.api.fetch_one", return_value=_PARENT_ROW), \
         patch("mobile.api.owns", return_value=False):
        res = client.post("/api/mobile/v1/parent/children/999/face/deferral", headers=headers, json={"action": "approve"})
        assert res.status_code == 404
        assert res.get_json()["error"] == "child_not_found"


def test_face_deferral_invalid_action_rejected(client):
    headers = _parent_headers(101)
    with patch("mobile.api.fetch_one", return_value=_PARENT_ROW), \
         patch("mobile.api.owns", return_value=True):
        res = client.post("/api/mobile/v1/parent/children/202/face/deferral", headers=headers, json={"action": "maybe"})
        assert res.status_code == 400
        assert res.get_json()["error"] == "invalid_action"


def test_face_deferral_approve_sets_skipped_and_notifies(client):
    headers = _parent_headers(101)
    with patch("mobile.api.fetch_one", side_effect=[_PARENT_ROW, {"child_id": 202}]), \
         patch("mobile.api.owns", return_value=True), \
         patch("mobile.api.execute") as execute, \
         patch("mobile.api.log") as audit_log, \
         patch("mobile.api.notify") as notify:
        res = client.post("/api/mobile/v1/parent/children/202/face/deferral", headers=headers, json={"action": "approve"})
        assert res.status_code == 200
        body = res.get_json()
        assert body["ok"] is True
        assert body["face_enrollment_skipped"] is True
        execute.assert_called_once()
        sql, params = execute.call_args[0]
        assert "face_enrollment_skipped" in sql
        assert params == (True, 202)
        audit_log.assert_called_once()
        assert audit_log.call_args[0][1] == "FACE_DEFERRAL_APPROVED"
        notify.assert_called_once()
        assert notify.call_args[0][0] == 202
        assert notify.call_args[0][1] == "FACE_DEFERRAL"


def test_face_deferral_reject_clears_skipped(client):
    headers = _parent_headers(101)
    with patch("mobile.api.fetch_one", side_effect=[_PARENT_ROW, {"child_id": 202}]), \
         patch("mobile.api.owns", return_value=True), \
         patch("mobile.api.execute") as execute, \
         patch("mobile.api.log") as audit_log, \
         patch("mobile.api.notify"):
        res = client.post("/api/mobile/v1/parent/children/202/face/deferral", headers=headers, json={"action": "reject"})
        assert res.status_code == 200
        assert res.get_json()["face_enrollment_skipped"] is False
        assert execute.call_args[0][1] == (False, 202)
        assert audit_log.call_args[0][1] == "FACE_DEFERRAL_REJECTED"


def test_child_face_skip_still_403_without_parent_approval(client):
    headers = _child_headers(202)
    with patch("mobile.api.fetch_one", side_effect=[_CHILD_ROW, {"face_enrollment_skipped": False}]):
        res = client.post("/api/mobile/v1/kids/face/skip", headers=headers)
        assert res.status_code == 403
        assert res.get_json()["error"] == "parent_approval_required"


def test_child_face_skip_ok_after_parent_approval(client):
    headers = _child_headers(202)
    with patch("mobile.api.fetch_one", side_effect=[_CHILD_ROW, {"face_enrollment_skipped": True}]):
        res = client.post("/api/mobile/v1/kids/face/skip", headers=headers)
        assert res.status_code == 200
        assert res.get_json()["ok"] is True
        body = res.get_json()
        assert body["deferred"] is True
        assert body["skipped"] is True
        assert "quiz_required" in body
