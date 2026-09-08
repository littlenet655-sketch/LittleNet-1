"""Real PostgreSQL authenticated role smoke for college-submission verification.

This module is intentionally skipped in the normal unit suite. CI enables it in a
separate job with a disposable PostgreSQL service so Kid/Parent/Admin route guards
are exercised against the actual schema instead of mocks.
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

        # Live account status is authoritative; a stale signed session must stop
        # working immediately once the account is suspended in PostgreSQL.
        _login(client, PARENT_ID, "PARENT", "CI Parent")
        _db_exec("UPDATE users SET account_status='SUSPENDED' WHERE user_id=%s", (PARENT_ID,))
        suspended = client.get(f"/parent/usage-report/?child_id={CHILD_ID}", follow_redirects=False)
        assert suspended.status_code in {302, 403}

        _db_exec("UPDATE users SET account_status='ACTIVE' WHERE user_id=%s", (PARENT_ID,))
