# Complete Level 2 Real-Service E2E test suite for LittleNet
# Verifies real database persistence, real moderation lifecycle, and real parent controls.

import os
import pytest
from io import BytesIO
import psycopg2
from psycopg2.extras import RealDictCursor
from mobile.api import _issue_token

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_REAL_POSTGRES_E2E") != "1",
    reason="requires disposable PostgreSQL service",
)

DB_URL = os.environ.get('DATABASE_URL', 'postgresql://postgres:littlenet@localhost:5433/safeconnect_db')

PARENT_ID = 999101
PARENT_EMAIL = 'real_parent_e2e@littlenet.local'
PARENT_PASS = 'P@ssword123!'

CHILD_A_ID = 999201
CHILD_A_USERNAME = 'real_kid_alpha'
CHILD_A_PASS = 'KidAlpha123!'

CHILD_B_ID = 999202
CHILD_B_USERNAME = 'real_kid_beta'
CHILD_B_PASS = 'KidBeta123!'

ADMIN_ID = 999301
ADMIN_EMAIL = 'real_admin_e2e@littlenet.local'

def _get_db():
    return psycopg2.connect(DB_URL)

def _db_exec(query, params=None):
    with _get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(query, params or ())
        conn.commit()

def _db_fetchone(query, params=None):
    with _get_db() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params or ())
            return cur.fetchone()

def _auth_header(user_id, role, full_name):
    token = _issue_token({'user_id': user_id, 'role': role, 'full_name': full_name})
    return {'Authorization': f'Bearer {token}'}

def _seed_test_users():
    _db_exec('DELETE FROM users WHERE user_id IN (%s, %s, %s, %s)', (PARENT_ID, CHILD_A_ID, CHILD_B_ID, ADMIN_ID))
    _db_exec(
        """INSERT INTO users(user_id, username, full_name, email, password_hash, role, age, dob, account_status)
           VALUES (%s, 'real_parent', 'Real Parent E2E', %s, 'x', 'PARENT', NULL, '1985-01-01', 'ACTIVE'),
                  (%s, 'real_kid_alpha', 'Real Kid Alpha', 'child_a_e2e@littlenet.local', 'x', 'CHILD', 11, '2015-01-01', 'ACTIVE'),
                  (%s, 'real_kid_beta', 'Real Kid Beta', 'child_b_e2e@littlenet.local', 'x', 'CHILD', 12, '2014-06-01', 'ACTIVE'),
                  (%s, 'real_admin', 'Real Admin E2E', %s, 'x', 'ADMIN', NULL, '1984-01-01', 'ACTIVE')""",
        (PARENT_ID, PARENT_EMAIL, CHILD_A_ID, CHILD_B_ID, ADMIN_ID, ADMIN_EMAIL)
    )
    _db_exec('DELETE FROM parent_child_map WHERE parent_email=%s OR child_id IN (%s, %s)', (PARENT_EMAIL, CHILD_A_ID, CHILD_B_ID))
    _db_exec(
        """INSERT INTO parent_child_map(
              child_id, parent_id, parent_name, parent_email, approved, approved_at,
              approval_status, parent_verified, verified_parent_id, verified_at
           )
           VALUES (%s, %s, 'Real Parent E2E', %s, TRUE, NOW(), 'APPROVED', TRUE, %s, NOW()),
                  (%s, %s, 'Real Parent E2E', %s, TRUE, NOW(), 'APPROVED', TRUE, %s, NOW())""",
        (CHILD_A_ID, PARENT_ID, PARENT_EMAIL, PARENT_ID, CHILD_B_ID, PARENT_ID, PARENT_EMAIL, PARENT_ID)
    )
    _db_exec('DELETE FROM parent_safety_settings WHERE child_id IN (%s, %s)', (CHILD_A_ID, CHILD_B_ID))
    _db_exec(
        """INSERT INTO parent_safety_settings(child_id, parent_id, safety_level)
           VALUES (%s, %s, 'STRICT'),
                  (%s, %s, 'STRICT')""",
        (CHILD_A_ID, PARENT_ID, CHILD_B_ID, PARENT_ID)
    )
    _db_exec('DELETE FROM face_profiles WHERE child_id IN (%s, %s)', (CHILD_A_ID, CHILD_B_ID))
    _db_exec(
        """INSERT INTO face_profiles(child_id, embedding, model_name)
           VALUES (%s, '[]'::jsonb, 'E2E'),
                  (%s, '[]'::jsonb, 'E2E')
           ON CONFLICT (child_id) DO UPDATE SET embedding=EXCLUDED.embedding""",
        (CHILD_A_ID, CHILD_B_ID)
    )
    _db_exec('DELETE FROM child_profiles WHERE child_id IN (%s, %s)', (CHILD_A_ID, CHILD_B_ID))
    _db_exec(
        """INSERT INTO child_profiles(child_id, parent_id, full_name, bio, school_name, current_class)
           VALUES (%s, %s, 'Real Kid Alpha', 'Robotics and astronomy explorer', 'LittleNet STEM Academy', 'Grade 6'),
                  (%s, %s, 'Real Kid Beta', 'Coding and science creator', 'LittleNet STEM Academy', 'Grade 6')
           ON CONFLICT (child_id) DO UPDATE SET school_name=EXCLUDED.school_name, current_class=EXCLUDED.current_class""",
        (CHILD_A_ID, PARENT_ID, CHILD_B_ID, PARENT_ID)
    )

def _safe_signals(category: str):
    return {
        "adult_score": 0.0,
        "violence_score": 0.0,
        "weapon_score": 0.0,
        "toxicity_score": 0.0,
        "general_score": 0.0,
        "category": category,
        "partial_safety_failure": False,
        "total_safety_failure": False,
    }

def test_real_authenticated_social_flow_e2e(monkeypatch):
    """Phase E: Complete authenticated social lifecycle."""
    _seed_test_users()
    from safety.policy import Decision
    import mobile.api as mobile_api
    import services.media_persistence as media_persistence

    def fake_evaluate(child_id, content_type, payload, adult_threshold=0.40):
        category = str(content_type or "TEXT").upper()
        return _safe_signals(category), Decision("ALLOW", 0.0, "e2e allow")

    monkeypatch.setattr(mobile_api, "evaluate", fake_evaluate)
    monkeypatch.setattr(
        media_persistence,
        "persist_before_db",
        lambda path, namespace, uid: f"uploads/r2/{namespace}/{uid}/real_{os.path.basename(path)}",
    )
    monkeypatch.setattr(media_persistence, "rollback_reference", lambda *_a, **_k: None)

    from app import create_app
    app = create_app()
    app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)

    p_hdr = _auth_header(PARENT_ID, 'PARENT', 'Real Parent')
    ca_hdr = _auth_header(CHILD_A_ID, 'CHILD', 'Real Kid Alpha')
    cb_hdr = _auth_header(CHILD_B_ID, 'CHILD', 'Real Kid Beta')

    with app.test_client() as client:
        # 1. Verify parent session & child relationships via parent dashboard
        p_dash = client.get('/api/mobile/v1/parent/dashboard', headers=p_hdr)
        assert p_dash.status_code == 200
        kids = p_dash.get_json().get('children', [])
        assert any(k['user_id'] == CHILD_A_ID for k in kids)
        assert any(k['user_id'] == CHILD_B_ID for k in kids)

        # 2. Child A accesses feed
        feed_a = client.get('/api/mobile/v1/kids/home', headers=ca_hdr)
        assert feed_a.status_code == 200
        assert 'posts' in feed_a.get_json()

        # 3. Child A creates clean text post
        text_resp = client.post(
            '/api/mobile/v1/kids/posts',
            headers=ca_hdr,
            data={'caption': 'Had a wonderful day learning astronomy and playing robotics!', 'kind': 'post'}
        )
        assert text_resp.status_code == 200, text_resp.get_json()
        post_id = text_resp.get_json()['post_id']
        assert post_id > 0

        # Verify DB persistence of text post
        row_post = _db_fetchone('SELECT * FROM posts WHERE post_id=%s', (post_id,))
        assert row_post is not None
        assert row_post['child_id'] == CHILD_A_ID
        assert row_post['is_safe'] is True
        assert row_post['moderation_status'] == 'ALLOWED'

        # 4. Child A creates image post with clean caption
        img_bytes = BytesIO(b'\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xdb')
        img_resp = client.post(
            '/api/mobile/v1/kids/posts',
            headers=ca_hdr,
            data={'caption': 'Exploring the stars and planets with my science project', 'kind': 'post', 'media': (img_bytes, 'science_stars.jpg', 'image/jpeg')},
            content_type='multipart/form-data'
        )
        assert img_resp.status_code == 200, img_resp.get_json()
        img_post_id = img_resp.get_json()['post_id']

        # Verify storage reference was generated and saved
        img_row = _db_fetchone('SELECT * FROM posts WHERE post_id=%s', (img_post_id,))
        assert img_row['media_path'].startswith('uploads/r2/posts/')

        # Child A refreshes feed and confirms their own posts are present
        feed_a_refreshed = client.get('/api/mobile/v1/kids/home', headers=ca_hdr)
        assert feed_a_refreshed.status_code == 200
        a_posts = feed_a_refreshed.get_json().get('posts', [])
        assert any(p['post_id'] == post_id for p in a_posts)
        assert any(p['post_id'] == img_post_id for p in a_posts)

        # 5. Child B follows Child A (connection request)
        follow_resp = client.post(f'/api/mobile/v1/kids/follow/{CHILD_A_ID}', headers=cb_hdr)
        assert follow_resp.status_code == 200
        assert follow_resp.get_json()['status'] == 'pending'

        # 6. Two-Parent Friendship Handshake:
        # Step 6a: Sender's parent approves outgoing request
        appr_resp1 = client.post(
            '/api/mobile/v1/parent/follow-requests/action',
            headers=p_hdr,
            json={'child_id': CHILD_B_ID, 'target_id': CHILD_A_ID, 'action': 'approve'}
        )
        assert appr_resp1.status_code == 200
        assert appr_resp1.get_json()['ok'] is True

        # Step 6b: Receiver's parent approves incoming request
        appr_resp2 = client.post(
            '/api/mobile/v1/parent/follow-requests/action',
            headers=p_hdr,
            json={'child_id': CHILD_A_ID, 'target_id': CHILD_B_ID, 'action': 'approve'}
        )
        assert appr_resp2.status_code == 200
        assert appr_resp2.get_json()['ok'] is True

        # Verify friendship is ACTIVE and approved on both rows in DB
        rel1 = _db_fetchone('SELECT approved, approval_stage FROM followers WHERE child_id=%s AND following_child_id=%s', (CHILD_B_ID, CHILD_A_ID))
        assert rel1 and rel1['approved'] is True and rel1['approval_stage'] == 'ACTIVE'
        rel2 = _db_fetchone('SELECT approved, approval_stage FROM followers WHERE child_id=%s AND following_child_id=%s', (CHILD_A_ID, CHILD_B_ID))
        assert rel2 and rel2['approved'] is True and rel2['approval_stage'] == 'ACTIVE'

        # 7. Now that Child B is approved follower, Child B feed contains Child A posts!
        feed_b = client.get('/api/mobile/v1/kids/home', headers=cb_hdr)
        assert feed_b.status_code == 200
        items = feed_b.get_json().get('posts', [])
        assert any(it['post_id'] == post_id for it in items)

        # 8. Child B likes Child A post
        like_resp = client.post(f'/api/mobile/v1/kids/posts/{post_id}/like', headers=cb_hdr)
        assert like_resp.status_code == 200
        assert like_resp.get_json()['liked'] is True

        # Verify like in DB
        like_row = _db_fetchone('SELECT 1 FROM likes WHERE post_id=%s AND child_id=%s', (post_id, CHILD_B_ID))
        assert like_row is not None

        # 9. Child B comments on Child A post
        comm_resp = client.post(
            f'/api/mobile/v1/kids/posts/{post_id}/comment',
            headers=cb_hdr,
            json={'text': 'Great science build! Let us test it together.'}
        )
        assert comm_resp.status_code == 200
        comm_id = comm_resp.get_json()['comment_id']

        # Verify comment in DB
        comm_row = _db_fetchone('SELECT * FROM comments WHERE comment_id=%s', (comm_id,))
        assert comm_row is not None
        assert comm_row['comment_text'] == 'Great science build! Let us test it together.'

        # 10. Direct messaging between Child A and Child B via mobile chat endpoint
        dm = client.post(
            f'/api/mobile/v1/kids/chat/{CHILD_A_ID}',
            headers=cb_hdr,
            json={'message_text': 'See you at the robotics club tomorrow!'}
        )
        assert dm.status_code == 200, dm.get_data(as_text=True)

        # Verify message persistence in DB
        msg_row = _db_fetchone(
            'SELECT * FROM child_messages WHERE sender_child_id=%s AND receiver_child_id=%s ORDER BY child_message_id DESC LIMIT 1',
            (CHILD_B_ID, CHILD_A_ID)
        )
        assert msg_row is not None
        assert msg_row['message_text'] == 'See you at the robotics club tomorrow!'
        assert msg_row['moderation_status'] == 'ALLOWED'

        # Verify recipient inbox receives message
        inbox = client.get('/api/mobile/v1/kids/messages', headers=ca_hdr)
        assert inbox.status_code == 200
        assert inbox.get_json().get('ok') is True

def test_real_safety_moderation_lifecycle_e2e():
    """Phase F: Complete moderation lifecycle (ALLOW, REVIEW, BLOCK, Parent Review, Admin Block)."""
    _seed_test_users()
    from app import create_app
    app = create_app()
    app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)

    p_hdr = _auth_header(PARENT_ID, 'PARENT', 'Real Parent')
    ca_hdr = _auth_header(CHILD_A_ID, 'CHILD', 'Real Child A')

    with app.test_client() as client:
        # 1. Hard block test with severe abuse keyword
        block_resp = client.post(
            '/api/mobile/v1/kids/posts',
            headers=ca_hdr,
            data={'caption': 'I will severely harm someone right now kill', 'kind': 'post'}
        )
        assert block_resp.status_code == 400
        err_json = block_resp.get_json()
        assert err_json.get('blocked') is True
        assert err_json.get('error') == 'content_blocked'

        # Verify hard block persisted in moderation_events
        ev = _db_fetchone(
            'SELECT * FROM moderation_events WHERE child_id=%s AND content_type=%s ORDER BY event_id DESC LIMIT 1',
            (CHILD_A_ID, 'TEXT')
        )
        assert ev is not None
        assert ev['decision'] == 'BLOCK'

        # Verify parent notification was created
        alert = _db_fetchone(
            'SELECT * FROM parent_notifications WHERE child_id=%s AND notification_type=%s ORDER BY notification_id DESC LIMIT 1',
            (CHILD_A_ID, 'CONTENT_BLOCKED')
        )
        assert alert is not None

        # 2. Test soft review lifecycle:
        # Create a post held for parent review
        _db_exec(
            """INSERT INTO posts(child_id, media_type, caption, is_safe, moderation_status, moderation_reason)
               VALUES (%s, 'TEXT', 'Borderline test post for moderation review', FALSE, 'REVIEW', 'possible risk')""",
            (CHILD_A_ID,)
        )
        p_row = _db_fetchone('SELECT post_id FROM posts WHERE child_id=%s ORDER BY post_id DESC LIMIT 1', (CHILD_A_ID,))
        rev_post_id = p_row['post_id']

        _db_exec(
            """INSERT INTO moderation_events(child_id, content_type, content_id, risk_score, decision, reason, status)
               VALUES (%s, 'TEXT', %s, 55.0, 'REVIEW', 'possible risk', 'OPEN')""",
            (CHILD_A_ID, rev_post_id)
        )
        e_row = _db_fetchone('SELECT event_id FROM moderation_events WHERE child_id=%s AND status=%s ORDER BY event_id DESC LIMIT 1', (CHILD_A_ID, 'OPEN'))
        rev_event_id = e_row['event_id']

        # 3. Parent reviews and APPROVES the event via mobile API
        appr_resp = client.post(
            f'/api/mobile/v1/parent/safety/{rev_event_id}',
            headers=p_hdr,
            json={'action': 'APPROVE'}
        )
        assert appr_resp.status_code == 200
        assert appr_resp.get_json()['ok'] is True

        # Verify post is now ALLOWED and is_safe=TRUE
        post_after_appr = _db_fetchone('SELECT moderation_status, is_safe FROM posts WHERE post_id=%s', (rev_post_id,))
        assert post_after_appr['moderation_status'] == 'ALLOWED'
        assert post_after_appr['is_safe'] is True

        # Verify event status resolved and review recorded in moderation_reviews
        ev_after = _db_fetchone('SELECT status FROM moderation_events WHERE event_id=%s', (rev_event_id,))
        assert ev_after['status'] == 'RESOLVED'
        rev_rec = _db_fetchone('SELECT * FROM moderation_reviews WHERE event_id=%s', (rev_event_id,))
        assert rev_rec is not None
        assert rev_rec['action'] == 'APPROVE'

def test_real_parent_screentime_and_controls_enforcement_e2e():
    """Phase G: Server-side enforcement of parent controls and screen-time."""
    _seed_test_users()
    from app import create_app
    app = create_app()
    app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)

    p_hdr = _auth_header(PARENT_ID, 'PARENT', 'Real Parent')
    ca_hdr = _auth_header(CHILD_A_ID, 'CHILD', 'Real Child A')

    with app.test_client() as client:
        # 1. Parent disables posting for Child A
        ctrl_resp = client.put(
            f'/api/mobile/v1/parent/controls/{CHILD_A_ID}',
            headers=p_hdr,
            json={'allow_posting': False, 'allow_messaging': True}
        )
        assert ctrl_resp.status_code == 200
        assert ctrl_resp.get_json()['ok'] is True

        # 2. Child A attempts to post -> Must be gated with HTTP 403 disabled_by_parent
        post_gated = client.post(
            '/api/mobile/v1/kids/posts',
            headers=ca_hdr,
            data={'caption': 'Testing disabled post', 'kind': 'post'}
        )
        assert post_gated.status_code == 403
        assert post_gated.get_json()['error'] == 'disabled_by_parent'
        assert post_gated.get_json()['feature'] == 'posting'

        # 3. Parent re-enables posting
        client.put(
            f'/api/mobile/v1/parent/controls/{CHILD_A_ID}',
            headers=p_hdr,
            json={'allow_posting': True}
        )

        # 4. Parent enforces quiet hours
        client.put(
            f'/api/mobile/v1/parent/controls/{CHILD_A_ID}',
            headers=p_hdr,
            json={'quiet_hours_enabled': True, 'quiet_start': '00:00', 'quiet_end': '23:59'}
        )

        # Child A attempts to access feed during active quiet hours -> HTTP 423
        quiet_gated = client.get('/api/mobile/v1/kids/home', headers=ca_hdr)
        assert quiet_gated.status_code == 423
        assert quiet_gated.get_json()['error'] == 'quiet_hours'
        assert quiet_gated.get_json()['gate'] == 'quiet_hours'

        # 5. Disable quiet hours to restore normal operation
        client.put(
            f'/api/mobile/v1/parent/controls/{CHILD_A_ID}',
            headers=p_hdr,
            json={'quiet_hours_enabled': False}
        )
        restored = client.get('/api/mobile/v1/kids/home', headers=ca_hdr)
        assert restored.status_code == 200
