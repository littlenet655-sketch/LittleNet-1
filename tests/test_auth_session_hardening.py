import os
import pytest
from itsdangerous import URLSafeTimedSerializer
from mobile.api import _AUTH_SALT

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:littlenet@localhost:5433/safeconnect_db",
)

from app import create_app
from database.connection import execute


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_auth_missing_token(client):
    res = client.get("/api/mobile/v1/me")
    assert res.status_code == 401
    assert res.get_json()["error"] == "mobile_auth_required"


def test_auth_invalid_token(client):
    res = client.get(
        "/api/mobile/v1/me",
        headers={"Authorization": "Bearer not-a-valid-token"},
    )
    assert res.status_code == 401
    assert res.get_json()["error"] == "mobile_auth_required"


def test_auth_expired_token(client):
    serializer = URLSafeTimedSerializer(client.application.config["SECRET_KEY"])
    bad_token = serializer.dumps({"uid": 101, "role": "CHILD"}, salt="WRONG_SALT")
    res = client.get(
        "/api/mobile/v1/me",
        headers={"Authorization": f"Bearer {bad_token}"},
    )
    assert res.status_code == 401
    assert res.get_json()["error"] == "mobile_auth_required"


def test_auth_role_forbidden(client, monkeypatch):
    serializer = URLSafeTimedSerializer(client.application.config["SECRET_KEY"])
    token = serializer.dumps({"uid": 9991, "role": "CHILD"}, salt=_AUTH_SALT)

    from mobile import api

    def mock_fetch_one(query, params):
        if "FROM users WHERE user_id" in query:
            return {
                "user_id": 9991,
                "username": "child_user",
                "full_name": "Child User",
                "email": "c@example.com",
                "role": "CHILD",
                "age": 10,
                "account_status": "ACTIVE",
            }
        return None

    monkeypatch.setattr(api, "fetch_one", mock_fetch_one)

    # Parent dashboard requires role PARENT, CHILD token gives 403 role_forbidden
    res = client.get(
        "/api/mobile/v1/parent/dashboard",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 403
    assert res.get_json()["error"] == "role_forbidden"


def test_auth_token_role_mismatch(client, monkeypatch):
    serializer = URLSafeTimedSerializer(client.application.config["SECRET_KEY"])
    # Token claims PARENT, but DB has user as CHILD
    token = serializer.dumps({"uid": 9992, "role": "PARENT"}, salt=_AUTH_SALT)

    from mobile import api

    def mock_fetch_one(query, params):
        if "FROM users WHERE user_id" in query:
            return {
                "user_id": 9992,
                "username": "mismatch_user",
                "full_name": "Mismatch User",
                "email": "m@example.com",
                "role": "CHILD",
                "age": 10,
                "account_status": "ACTIVE",
            }
        return None

    monkeypatch.setattr(api, "fetch_one", mock_fetch_one)

    res = client.get(
        "/api/mobile/v1/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 401
    assert res.get_json()["error"] == "token_role_mismatch"


def test_auth_suspended_account(client, monkeypatch):
    serializer = URLSafeTimedSerializer(client.application.config["SECRET_KEY"])
    token = serializer.dumps({"uid": 8888, "role": "CHILD"}, salt=_AUTH_SALT)

    from mobile import api

    def mock_fetch_one(query, params):
        if "FROM users WHERE user_id" in query:
            return {
                "user_id": 8888,
                "username": "suspended_kid",
                "full_name": "Suspended Kid",
                "email": "s@example.com",
                "role": "CHILD",
                "age": 11,
                "account_status": "SUSPENDED",
            }
        return None

    monkeypatch.setattr(api, "fetch_one", mock_fetch_one)

    res = client.get(
        "/api/mobile/v1/kids/home",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 401
    assert res.get_json()["error"] == "account_suspended"


def test_auth_logout_token_revocation(client, monkeypatch):
    serializer = URLSafeTimedSerializer(client.application.config["SECRET_KEY"])
    token = serializer.dumps({"uid": 7777, "role": "PARENT"}, salt=_AUTH_SALT)

    revoked_set = set()
    from mobile import api

    def mock_fetch_one(query, params):
        if "FROM revoked_tokens WHERE token_hash" in query:
            return {"1": 1} if params[0] in revoked_set else None
        if "FROM users WHERE user_id" in query:
            return {
                "user_id": 7777,
                "username": "logout_parent",
                "full_name": "Logout Parent",
                "email": "lp@example.com",
                "role": "PARENT",
                "age": 38,
                "account_status": "ACTIVE",
            }
        return None

    def mock_execute(query, params):
        if "INSERT INTO revoked_tokens" in query:
            revoked_set.add(params[0])
        return 1

    monkeypatch.setattr(api, "fetch_one", mock_fetch_one)
    monkeypatch.setattr(api, "execute", mock_execute)

    # 1. First call to me succeeds
    res1 = client.get(
        "/api/mobile/v1/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res1.status_code == 200
    assert res1.get_json()["user"]["username"] == "logout_parent"

    # 2. Call logout
    res_logout = client.post(
        "/api/mobile/v1/auth/logout",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res_logout.status_code == 200
    assert res_logout.get_json()["ok"] is True

    # 3. Subsequent call with same token MUST fail with 401 mobile_auth_required
    res_reuse = client.get(
        "/api/mobile/v1/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert res_reuse.status_code == 401
    assert res_reuse.get_json()["error"] == "mobile_auth_required"


def test_parent_reset_child_password(client, monkeypatch):
    serializer = URLSafeTimedSerializer(client.application.config["SECRET_KEY"])
    token = serializer.dumps({"uid": 5555, "role": "PARENT"}, salt=_AUTH_SALT)

    from mobile import api

    def mock_fetch_one(query, params):
        if "FROM users WHERE user_id" in query:
            return {
                "user_id": 5555,
                "username": "parent_reset",
                "full_name": "Parent Reset",
                "email": "pr@example.com",
                "role": "PARENT",
                "age": 40,
                "account_status": "ACTIVE",
            }
        return None

    monkeypatch.setattr(api, "fetch_one", mock_fetch_one)
    monkeypatch.setattr(api, "owns", lambda pid, cid: pid == 5555 and cid == 6666)
    executed_updates = []
    monkeypatch.setattr(api, "execute", lambda q, p: executed_updates.append((q, p)))

    res = client.post(
        "/api/mobile/v1/parent/children/6666/reset-password",
        headers={"Authorization": f"Bearer {token}"},
        json={"new_password": "superSafeChildPassword123"},
    )
    assert res.status_code == 200
    assert res.get_json()["ok"] is True
    assert len(executed_updates) == 1
    assert "UPDATE users SET password_hash" in executed_updates[0][0]
