"""Real PostgreSQL authenticated role smoke for college-submission verification.

This module is intentionally skipped in the normal unit suite. CI enables it in a
separate job with a disposable PostgreSQL service so Kid/Parent/Admin browser and
native bearer-API guards are exercised against the actual production migration
chain instead of mocks.
"""
import os

import pytest


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_REAL_POSTGRES_E2E") != "1",
    reason="requires disposable PostgreSQL service",
)


CHILD_ID = 9101
PARENT_ID = 9102
ADMIN_ID = 9103


def _db_exec(sql, params=()):
    import psycopg2

    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
        conn.commit()
    finally:
        conn.close()


def _db_fetchone(sql, params=()):
    import psycopg2
    from psycopg2.extras import RealDictCursor

    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def _seed_role_fixture():
    _db_exec(
        """
        DELETE FROM users WHERE user_id IN (%s,%s,%s);
        INSERT INTO users(user_id,username,full_name,email,password_hash,role,age,dob,account_status)
        VALUES
          (%s,'ci_child','CI Child','ci-child@example.invalid','x','CHILD',12,'2014-01-01','ACTIVE'),
          (%s,'ci_parent','CI Parent','ci-parent@example.invalid','x','PARENT',NULL,'1985-01-01','ACTIVE'),
          (%s,'ci_admin','CI Admin','ci-admin@example.invalid','x','ADMIN',NULL,'1980-01-01','ACTIVE');
        """,
        (CHILD_ID, PARENT_ID, ADMIN_ID, CHILD_ID, PARENT_ID, ADMIN_ID),
    )
    _db_exec(
        """
        INSERT INTO face_profiles(child_id,embedding,model_name)
        VALUES(%s,'[]'::jsonb,'CI')
        ON CONFLICT(child_id) DO UPDATE SET embedding=EXCLUDED.embedding;
        """,
        (CHILD_ID,),
    )
    _db_exec(
        """
        INSERT INTO parent_child_map(child_id,parent_id,parent_name,parent_email,approved,approved_at,approval_status,parent_verified,verified_parent_id,verified_at)
        VALUES(%s,%s,'CI Parent','ci-parent@example.invalid',TRUE,NOW(),'APPROVED',TRUE,%s,NOW())
        ON CONFLICT(child_id,parent_email) DO UPDATE SET
          parent_id=EXCLUDED.parent_id,
          approved=TRUE,
          approved_at=NOW(),
          approval_status='APPROVED',
          parent_verified=TRUE,
          verified_parent_id=EXCLUDED.verified_parent_id,
          verified_at=NOW();
        """,
        (CHILD_ID, PARENT_ID, PARENT_ID),
    )


def _login(client, user_id, role, name):
    with client.session_transaction() as sess:
        sess.clear()
        sess["user_id"] = user_id
        sess["role"] = role
        sess["full_name"] = name


def _mobile_headers(user_id, role, name):
    from mobile.api import _issue_token

    token = _issue_token({"user_id": user_id, "role": role, "full_name": name})
    return {"Authorization": f"Bearer {token}"}


def test_real_postgres_kid_parent_admin_routes_and_live_status_guards():
    _seed_role_fixture()

    from app import create_app

    app = create_app()
    app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)

    with app.test_client() as client:
        _login(client, CHILD_ID, "CHILD", "CI Child")
        child = client.get("/saved/", follow_redirects=False)
        assert child.status_code == 200, child.get_data(as_text=True)[:500]

        _login(client, PARENT_ID, "PARENT", "CI Parent")
        parent = client.get(f"/parent/usage-report/?child_id={CHILD_ID}", follow_redirects=False)
        assert parent.status_code == 200, parent.get_data(as_text=True)[:500]

        _login(client, ADMIN_ID, "ADMIN", "CI Admin")
        admin = client.get("/admin/users/", follow_redirects=False)
        assert admin.status_code == 200, admin.get_data(as_text=True)[:500]

        # Role confusion must not grant access to another mode.
        _login(client, CHILD_ID, "CHILD", "CI Child")
        wrong_role = client.get("/admin/users/", follow_redirects=False)
        assert wrong_role.status_code in {302, 401, 403}

        # Native Flutter bearer routes must work against the same real database.
        kid_mobile = client.get(
            "/api/mobile/v1/kids/home",
            headers=_mobile_headers(CHILD_ID, "CHILD", "CI Child"),
        )
        assert kid_mobile.status_code == 200, kid_mobile.get_data(as_text=True)[:500]
        assert kid_mobile.get_json()["ok"] is True

        parent_mobile = client.get(
            "/api/mobile/v1/parent/dashboard",
            headers=_mobile_headers(PARENT_ID, "PARENT", "CI Parent"),
        )
        assert parent_mobile.status_code == 200, parent_mobile.get_data(as_text=True)[:500]
        assert any(int(k["user_id"]) == CHILD_ID for k in parent_mobile.get_json()["children"])

        admin_mobile = client.get(
            "/api/mobile/v1/admin/dashboard",
            headers=_mobile_headers(ADMIN_ID, "ADMIN", "CI Admin"),
        )
        assert admin_mobile.status_code == 200, admin_mobile.get_data(as_text=True)[:500]

        # ESCALATE must append an audit-trail row while leaving the event open,
        # then a later final APPROVE must succeed for the same event. This proves
        # the production migration removed the old one-review-per-event trap.
        event = _db_fetchone(
            """INSERT INTO moderation_events(child_id,content_type,risk_score,decision,reason,status)
               VALUES(%s,'TEXT',55,'REVIEW','CI native escalation smoke','OPEN')
               RETURNING event_id""",
            (CHILD_ID,),
        )
        event_id = int(event["event_id"])
        admin_headers = _mobile_headers(ADMIN_ID, "ADMIN", "CI Admin")

        escalated = client.post(
            f"/api/mobile/v1/admin/reviews/{event_id}",
            headers=admin_headers,
            json={"action": "ESCALATE", "notes": "CI escalation"},
        )
        assert escalated.status_code == 200, escalated.get_data(as_text=True)[:500]
        assert escalated.get_json()["status"] == "OPEN"

        approved = client.post(
            f"/api/mobile/v1/admin/reviews/{event_id}",
            headers=admin_headers,
            json={"action": "APPROVE", "notes": "CI final decision"},
        )
        assert approved.status_code == 200, approved.get_data(as_text=True)[:500]
        assert approved.get_json()["status"] == "RESOLVED"
        reviews = _db_fetchone(
            "SELECT COUNT(*)::int n FROM moderation_reviews WHERE event_id=%s",
            (event_id,),
        )
        assert reviews["n"] == 2

        # Live account status is authoritative; a stale signed browser and
        # native token must stop working immediately after suspension.
        _login(client, PARENT_ID, "PARENT", "CI Parent")
        parent_headers = _mobile_headers(PARENT_ID, "PARENT", "CI Parent")
        _db_exec("UPDATE users SET account_status='SUSPENDED' WHERE user_id=%s", (PARENT_ID,))
        suspended = client.get(f"/parent/usage-report/?child_id={CHILD_ID}", follow_redirects=False)
        assert suspended.status_code in {302, 403}
        suspended_mobile = client.get("/api/mobile/v1/parent/dashboard", headers=parent_headers)
        assert suspended_mobile.status_code == 401

        _db_exec("UPDATE users SET account_status='ACTIVE' WHERE user_id=%s", (PARENT_ID,))
