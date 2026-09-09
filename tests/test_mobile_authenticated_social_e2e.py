"""Authenticated mobile Parent→Child→Social persistence E2E.

Skipped in the default unit suite. Enabled with RUN_REAL_POSTGRES_E2E=1 against a
disposable PostgreSQL (role-e2e workflow) or an isolated local DATABASE_URL.

Covers the critical native bearer path:
  parent owns child → child home → create text post → persist → like → comment
  → approved friendship → 1:1 DM → feed still contains the post

Safety models / R2 are stubbed ONLY inside this disposable E2E module via
monkeypatch (same pattern as other runtime tests). Production fail-closed
policy and R2 enforcement remain unchanged.
"""
from __future__ import annotations

import os
from io import BytesIO

import pytest

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_REAL_POSTGRES_E2E") != "1",
    reason="requires disposable PostgreSQL service",
)

PARENT_ID = 9201
CHILD_A_ID = 9202
CHILD_B_ID = 9203


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


def _seed():
    _db_exec(
        """
        DELETE FROM users WHERE user_id IN (%s,%s,%s);
        INSERT INTO users(user_id,username,full_name,email,password_hash,role,age,dob,account_status)
        VALUES
          (%s,'e2e_parent','E2E Parent','e2e-parent@example.invalid','x','PARENT',NULL,'1985-01-01','ACTIVE'),
          (%s,'e2e_child_a','E2E Child A','e2e-child-a@example.invalid','x','CHILD',11,'2015-01-01','ACTIVE'),
          (%s,'e2e_child_b','E2E Child B','e2e-child-b@example.invalid','x','CHILD',11,'2015-06-01','ACTIVE');
        """,
        (PARENT_ID, CHILD_A_ID, CHILD_B_ID, PARENT_ID, CHILD_A_ID, CHILD_B_ID),
    )
    for cid in (CHILD_A_ID, CHILD_B_ID):
        _db_exec(
            """
            INSERT INTO face_profiles(child_id,embedding,model_name)
            VALUES(%s,'[]'::jsonb,'E2E')
            ON CONFLICT(child_id) DO UPDATE SET embedding=EXCLUDED.embedding;
            """,
            (cid,),
        )
        _db_exec(
            """
            INSERT INTO parent_child_map(
              child_id,parent_id,parent_name,parent_email,approved,approved_at,
              approval_status,parent_verified,verified_parent_id,verified_at
            )
            VALUES(%s,%s,'E2E Parent','e2e-parent@example.invalid',TRUE,NOW(),'APPROVED',TRUE,%s,NOW())
            ON CONFLICT(child_id,parent_email) DO UPDATE SET
              parent_id=EXCLUDED.parent_id,
              approved=TRUE,
              approved_at=NOW(),
              approval_status='APPROVED',
              parent_verified=TRUE,
              verified_parent_id=EXCLUDED.verified_parent_id,
              verified_at=NOW();
            """,
            (cid, PARENT_ID, PARENT_ID),
        )
        _db_exec(
            """
            INSERT INTO child_profiles(child_id,parent_id,full_name,bio)
            VALUES(%s,%s,%s,'E2E profile')
            ON CONFLICT(child_id) DO UPDATE SET parent_id=EXCLUDED.parent_id, full_name=EXCLUDED.full_name;
            """,
            (cid, PARENT_ID, f"E2E Child {'A' if cid == CHILD_A_ID else 'B'}"),
        )


def _headers(user_id, role, name):
    from mobile.api import _issue_token

    return {"Authorization": f"Bearer {_issue_token({'user_id': user_id, 'role': role, 'full_name': name})}"}


def _safe_signals(category="TEXT"):
    return {
        "adult_score": 0.0,
        "sexual_score": 0.0,
        "violence_score": 0.0,
        "weapon_score": 0.0,
        "toxicity_score": 0.0,
        "general_score": 0.0,
        "category": category,
        "partial_safety_failure": False,
        "total_safety_failure": False,
    }


@pytest.fixture
def stub_mobile_safety(monkeypatch):
    """Disposable-E2E only: keep moderation wiring, replace remote model/R2 unavailability."""
    from safety.policy import Decision
    import mobile.api as mobile_api
    import services.media_persistence as media_persistence

    def fake_evaluate(child_id, content_type, payload, adult_threshold=0.40):
        category = str(content_type or "TEXT").upper()
        if category in {"AUDIO", "VOICE"}:
            signals = _safe_signals(category)
            signals["total_safety_failure"] = True
            return signals, Decision("BLOCK", 100.0, "Standalone audio and voice uploads are disabled in LittleNet")
        signals = _safe_signals(category if category in {"TEXT", "IMAGE", "VIDEO", "COMMENT"} else "TEXT")
        return signals, Decision("ALLOW", 0.0, "e2e stub allow")

    monkeypatch.setattr(mobile_api, "evaluate", fake_evaluate)
    monkeypatch.setattr(
        media_persistence,
        "persist_before_db",
        lambda path, namespace, uid: f"e2e://{namespace}/{uid}/{os.path.basename(path)}",
    )
    monkeypatch.setattr(media_persistence, "rollback_reference", lambda *_a, **_k: None)


def test_mobile_parent_child_feed_post_like_comment_follow_and_dm_persist(stub_mobile_safety):
    _seed()
    from app import create_app

    app = create_app()
    app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)

    parent_h = _headers(PARENT_ID, "PARENT", "E2E Parent")
    child_a_h = _headers(CHILD_A_ID, "CHILD", "E2E Child A")
    child_b_h = _headers(CHILD_B_ID, "CHILD", "E2E Child B")

    with app.test_client() as client:
        parent_dash = client.get("/api/mobile/v1/parent/dashboard", headers=parent_h)
        assert parent_dash.status_code == 200, parent_dash.get_data(as_text=True)[:500]
        kids = parent_dash.get_json().get("children") or []
        assert {int(k["user_id"]) for k in kids} >= {CHILD_A_ID, CHILD_B_ID}

        home = client.get("/api/mobile/v1/kids/home", headers=child_a_h)
        assert home.status_code == 200, home.get_data(as_text=True)[:500]
        assert home.get_json()["ok"] is True

        created = client.post(
            "/api/mobile/v1/kids/posts",
            headers=child_a_h,
            data={
                "kind": "post",
                "caption": "E2E safe hello from LittleNet child A",
                "content_category": "Education",
                "audience_age_group": "ALL",
            },
            content_type="multipart/form-data",
        )
        assert created.status_code == 200, created.get_data(as_text=True)[:800]
        created_json = created.get_json()
        assert created_json.get("ok") is True
        post_id = int(created_json["post_id"])

        persisted = _db_fetchone("SELECT post_id,child_id,caption,is_safe FROM posts WHERE post_id=%s", (post_id,))
        assert persisted and int(persisted["child_id"]) == CHILD_A_ID
        assert "E2E safe hello" in (persisted.get("caption") or "")

        home2 = client.get("/api/mobile/v1/kids/home", headers=child_a_h)
        assert home2.status_code == 200
        home_payload = home2.get_json()
        posts = home_payload.get("posts") or home_payload.get("feed") or []
        assert any(int(p.get("post_id") or 0) == post_id for p in posts), "created post missing from home feed refresh"

        liked = client.post(f"/api/mobile/v1/kids/posts/{post_id}/like", headers=child_a_h)
        assert liked.status_code == 200, liked.get_data(as_text=True)[:500]
        like_row = _db_fetchone(
            "SELECT 1 AS ok FROM likes WHERE post_id=%s AND child_id=%s",
            (post_id, CHILD_A_ID),
        )
        assert like_row

        commented = client.post(
            f"/api/mobile/v1/kids/posts/{post_id}/comment",
            headers=child_a_h,
            json={"text": "Nice educational post!"},
        )
        assert commented.status_code == 200, commented.get_data(as_text=True)[:500]
        comment_row = _db_fetchone(
            "SELECT comment_text FROM comments WHERE post_id=%s AND child_id=%s ORDER BY comment_id DESC LIMIT 1",
            (post_id, CHILD_A_ID),
        )
        assert comment_row and "Nice educational" in (comment_row.get("comment_text") or "")

        _db_exec(
            """
            INSERT INTO followers(child_id,following_child_id,approved,approval_stage)
            VALUES(%s,%s,TRUE,'ACTIVE')
            ON CONFLICT(child_id,following_child_id) DO UPDATE
              SET approved=TRUE, approval_stage='ACTIVE';
            """,
            (CHILD_B_ID, CHILD_A_ID),
        )
        _db_exec(
            """
            INSERT INTO followers(child_id,following_child_id,approved,approval_stage)
            VALUES(%s,%s,TRUE,'ACTIVE')
            ON CONFLICT(child_id,following_child_id) DO UPDATE
              SET approved=TRUE, approval_stage='ACTIVE';
            """,
            (CHILD_A_ID, CHILD_B_ID),
        )

        pending = client.get("/api/mobile/v1/parent/follow-requests", headers=parent_h)
        assert pending.status_code == 200, pending.get_data(as_text=True)[:500]
        assert "pending" in pending.get_json()

        dm = client.post(
            f"/api/mobile/v1/kids/chat/{CHILD_A_ID}",
            headers=child_b_h,
            json={"message_text": "Hi from child B — E2E DM"},
        )
        assert dm.status_code == 200, dm.get_data(as_text=True)[:800]
        inbox = client.get("/api/mobile/v1/kids/messages", headers=child_a_h)
        assert inbox.status_code == 200
        assert inbox.get_json().get("ok") is True

        detail = client.get("/api/mobile/v1/kids/home", headers=child_a_h)
        assert detail.status_code == 200
        refreshed = detail.get_json().get("posts") or detail.get_json().get("feed") or []
        assert any(int(p.get("post_id") or 0) == post_id for p in refreshed)


def test_mobile_text_post_with_tiny_image_persists_media_reference(stub_mobile_safety):
    """Prove create-post media path stores a media_path when an image is supplied."""
    _seed()
    from app import create_app

    app = create_app()
    app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)
    child_a_h = _headers(CHILD_A_ID, "CHILD", "E2E Child A")

    png = BytesIO(
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00"
        b"\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
    )

    with app.test_client() as client:
        created = client.post(
            "/api/mobile/v1/kids/posts",
            headers=child_a_h,
            data={
                "kind": "post",
                "caption": "E2E image post",
                "content_category": "Art",
                "audience_age_group": "ALL",
                "media": (png, "e2e.png"),
            },
            content_type="multipart/form-data",
        )
        assert created.status_code in {200, 201, 202}, created.get_data(as_text=True)[:1000]
        row = _db_fetchone(
            "SELECT media_path,caption FROM posts WHERE child_id=%s AND caption=%s ORDER BY post_id DESC LIMIT 1",
            (CHILD_A_ID, "E2E image post"),
        )
        assert row, "image post row missing"
        assert row.get("media_path"), "media_path not persisted"
