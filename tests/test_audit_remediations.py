import json
from pathlib import Path
from flask import Blueprint, Flask
from unittest.mock import MagicMock
from mobile.api import register_mobile_api, _issue_token

ROOT = Path(__file__).resolve().parents[1]


def _make_app():
    app = Flask(__name__)
    app.secret_key = "test-secret"
    bp = Blueprint("mobile_test", __name__)
    register_mobile_api(bp)
    app.register_blueprint(bp)
    return app


def test_cleartext_traffic_disabled_in_app_json():
    app_json = json.loads((ROOT / "mobile_app" / "app.json").read_text(encoding="utf-8"))
    assert app_json["expo"]["android"]["usesCleartextTraffic"] is False, "usesCleartextTraffic must be false for production safety"


def test_child_face_enroll_rejects_re_enrollment(monkeypatch):
    app = _make_app()
    user = {"user_id": 101, "role": "CHILD", "account_status": "ACTIVE", "full_name": "Test Child"}
    token = _issue_token(user)

    monkeypatch.setattr("mobile.api.fetch_one", lambda query, params=(): user if "FROM users" in query else None)
    monkeypatch.setattr("mobile.api.has_face_profile", lambda uid: True)

    with app.test_client() as client:
        resp = client.post(
            "/api/mobile/v1/kids/face/enroll",
            headers={"Authorization": f"Bearer {token}"},
            data={"photo": "test"},
        )
        assert resp.status_code == 409
        data = resp.get_json()
        assert data["error"] == "face_already_enrolled"


def test_parent_reset_child_face_endpoint(monkeypatch):
    app = _make_app()
    parent = {"user_id": 50, "role": "PARENT", "account_status": "ACTIVE", "full_name": "Parent"}
    token = _issue_token(parent)

    cleared = []
    monkeypatch.setattr("mobile.api.fetch_one", lambda query, params=(): parent if "FROM users" in query else None)
    monkeypatch.setattr("mobile.api.owns", lambda pid, cid: True)
    monkeypatch.setattr("mobile.api.clear_child_face", lambda cid: cleared.append(cid))
    monkeypatch.setattr("mobile.api.log", lambda *args, **kwargs: None)
    monkeypatch.setattr("mobile.api.notify", lambda *args, **kwargs: None)

    with app.test_client() as client:
        resp = client.post(
            "/api/mobile/v1/parent/child/101/reset-face",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["ok"] is True
        assert 101 in cleared


def test_mobile_logout_revokes_token(monkeypatch):
    app = _make_app()
    user = {"user_id": 101, "role": "CHILD", "account_status": "ACTIVE", "full_name": "Child"}
    token = _issue_token(user, usage_session_key="session-key-1")

    revocations = []
    monkeypatch.setattr("mobile.api.fetch_one", lambda query, params=(): user if "FROM users" in query else None)
    monkeypatch.setattr("mobile.api.close_session", lambda key: None)
    monkeypatch.setattr("mobile.api.execute", lambda query, params=(): revocations.append(params))

    with app.test_client() as client:
        resp = client.post(
            "/api/mobile/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        assert len(revocations) > 0
        assert revocations[0][1] == 101


def test_revoked_token_is_rejected(monkeypatch):
    app = _make_app()
    user = {"user_id": 101, "role": "CHILD", "account_status": "ACTIVE", "full_name": "Child"}
    token = _issue_token(user)

    monkeypatch.setattr(
        "mobile.api.fetch_one",
        lambda query, params=(): {"token_hash": "exists"} if "mobile_token_revocations" in query else user,
    )

    with app.test_client() as client:
        resp = client.get(
            "/api/mobile/v1/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 401
        data = resp.get_json()
        assert data["error"] == "token_revoked"


def test_v2_kids_heartbeat_normal_and_locked(monkeypatch):
    app = _make_app()
    user = {"user_id": 101, "role": "CHILD", "account_status": "ACTIVE", "full_name": "Child"}
    token = _issue_token(user)

    monkeypatch.setattr("mobile.api.fetch_one", lambda query, params=(): user if "FROM users" in query else None)
    monkeypatch.setattr("mobile.api._child_gate", lambda *args, **kwargs: None)
    monkeypatch.setattr("mobile.api.lock_state", lambda uid: (False, 45))
    monkeypatch.setattr("mobile.api.minutes_today", lambda uid: 15)

    with app.test_client() as client:
        resp = client.post(
            "/api/mobile/v2/kids/heartbeat",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["ok"] is True
        assert data["minutes_today"] == 15
        assert data["remaining_minutes"] == 45
        assert data["locked"] is False


def test_kids_profile_gated_during_quiet_hours(monkeypatch):
    app = _make_app()
    user = {"user_id": 101, "role": "CHILD", "account_status": "ACTIVE", "full_name": "Child"}
    token = _issue_token(user)

    monkeypatch.setattr("mobile.api.fetch_one", lambda query, params=(): user if "FROM users" in query else None)
    # Simulate child gate returning 423 quiet hours
    monkeypatch.setattr("mobile.api._child_gate", lambda *args, **kwargs: (app.response_class(
        response=json.dumps({"error": "quiet_hours", "gate": "quiet_hours"}),
        status=423,
        mimetype="application/json"
    )))

    with app.test_client() as client:
        resp = client.get(
            "/api/mobile/v1/kids/profile",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 423
        data = resp.get_json()
        assert data["error"] == "quiet_hours"


def test_upload_complete_rechecks_parent_controls(monkeypatch):
    app = _make_app()
    user = {"user_id": 101, "role": "CHILD", "account_status": "ACTIVE", "full_name": "Child"}
    token = _issue_token(user)

    monkeypatch.setattr("mobile.api.fetch_one", lambda query, params=(): user if "FROM users" in query else None)

    # Mock db connection cursor
    mock_conn = MagicMock()
    mock_cur = MagicMock()
    mock_conn.cursor.return_value = mock_cur
    mock_cur.fetchone.return_value = {
        "upload_id": "up-123",
        "child_id": 101,
        "kind": "POST",
        "status": "INITIATED",
        "object_key": "uploads/101/up-123/source.jpg",
    }
    monkeypatch.setattr("mobile.api.get_db_connection", lambda: mock_conn)

    # Simulate parent disabled posting in controls
    monkeypatch.setattr(
        "mobile.api._child_gate",
        lambda feature: (
            app.response_class(
                response=json.dumps({"error": "disabled_by_parent", "feature": feature}),
                status=403,
                mimetype="application/json"
            ) if feature == "posting" else None
        ),
    )

    with app.test_client() as client:
        resp = client.post(
            "/api/mobile/v2/uploads/up-123/complete",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403
        data = resp.get_json()
        assert data["error"] == "disabled_by_parent"
        assert data["feature"] == "posting"

