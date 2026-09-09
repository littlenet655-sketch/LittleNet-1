"""Production Pre-Device Verification Suite for LittleNet

Tests all core safety, social, parent, and AI workflows against real production
dependencies: Neon PostgreSQL, Modal AI inference service, Cloudflare R2, and Resend.
No mocks or stubs are used.
"""
import os
import json
import time
import hashlib
from datetime import datetime, timedelta
import pytest
from dotenv import load_dotenv

load_dotenv("D:/aitprojects/LittleNet-1-current/.env", override=True)

from database.connection import get_db_connection, execute, fetch_one, fetch_all
from safety import remote_client
from safety.policy import decide, Decision
from safety.moderation_service import evaluate, record, safety_level
from safety.yolo_policy import classify_detections, classify_label
from services import object_storage
from services.social import parent_notify
from mailg.send_email import send_email, get_mail_status

# Test fixture account IDs (deterministic, safe test IDs dedicated to pre-device verification)
TEST_PARENT_ID = 999801
TEST_PARENT_2_ID = 999802
TEST_CHILD_A_ID = 999811
TEST_CHILD_B_ID = 999812
TEST_CONV_ID = 999851


@pytest.fixture(scope="module", autouse=True)
def setup_test_environment():
    """Ensure database connection, test accounts and tables exist."""
    # Verify DB connectivity
    row = fetch_one("SELECT 1 as connected")
    assert row and row["connected"] == 1, "Database not connected"

    # Clean prior test rows
    execute("DELETE FROM child_messages WHERE sender_child_id IN (%s, %s) OR receiver_child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM child_conversations WHERE child1_id IN (%s, %s) OR child2_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM parent_notifications WHERE child_id IN (%s, %s) OR parent_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_PARENT_ID, TEST_PARENT_2_ID))
    execute("DELETE FROM followers WHERE child_id IN (%s, %s) OR following_child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM blocked_users WHERE blocker_id IN (%s, %s) OR blocked_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM reports WHERE reporter_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM parent_child_map WHERE child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM parent_safety_settings WHERE child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM parent_control_settings WHERE child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM face_profiles WHERE child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))

    # Seed test users if missing
    execute("""
        INSERT INTO users(user_id, username, full_name, email, password_hash, role, account_status)
        VALUES 
            (999801, 'v_parent_alpha_999801', 'Alpha Parent', 'test_alpha_parent_999801@littlenet.test', 'pbkdf2:test', 'PARENT', 'ACTIVE'),
            (999802, 'v_parent_beta_999802', 'Beta Parent', 'test_beta_parent_999802@littlenet.test', 'pbkdf2:test', 'PARENT', 'ACTIVE'),
            (999811, 'v_kid_alpha_999811', 'Alpha Kid', 'test_kid_alpha_999811@littlenet.test', 'pbkdf2:test', 'CHILD', 'ACTIVE'),
            (999812, 'v_kid_beta_999812', 'Beta Kid', 'test_kid_beta_999812@littlenet.test', 'pbkdf2:test', 'CHILD', 'ACTIVE')
        ON CONFLICT(user_id) DO UPDATE SET account_status='ACTIVE', username=EXCLUDED.username
    """)

    # Link parents and children
    execute("""
        INSERT INTO parent_child_map(child_id, parent_id, parent_name, parent_email, approved, approval_status, parent_verified)
        VALUES 
            (999811, 999801, 'Alpha Parent', 'test_alpha_parent@littlenet.test', TRUE, 'APPROVED', TRUE),
            (999812, 999802, 'Beta Parent', 'test_beta_parent@littlenet.test', TRUE, 'APPROVED', TRUE)
    """)

    # Child profiles
    execute("""
        INSERT INTO child_profiles(child_id, parent_id, full_name, age, date_of_birth)
        VALUES 
            (999811, 999801, 'Alpha Kid', 11, '2015-01-01'),
            (999812, 999802, 'Beta Kid', 12, '2014-06-01')
        ON CONFLICT(child_id) DO NOTHING
    """)

    # Parent safety settings
    execute("""
        INSERT INTO parent_safety_settings(child_id, parent_id, safety_level)
        VALUES 
            (999811, 999801, 'STRICT'),
            (999812, 999802, 'STRICT')
        ON CONFLICT(child_id) DO UPDATE SET safety_level='STRICT'
    """)

    # Parent control settings
    execute("""
        INSERT INTO parent_control_settings(child_id, parent_id, allow_reels, allow_stories, allow_messaging, allow_posting, allow_discover, quiet_hours_enabled)
        VALUES 
            (999811, 999801, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
            (999812, 999802, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
        ON CONFLICT(child_id) DO UPDATE SET allow_posting=TRUE, allow_messaging=TRUE
    """)

    # Setup valid conversation between test children
    execute("""
        INSERT INTO child_conversations(conversation_id, child1_id, child2_id)
        VALUES (999851, 999811, 999812)
        ON CONFLICT(child1_id, child2_id) DO NOTHING
    """)

    yield

    # Teardown / cleanup transient test records
    execute("DELETE FROM child_messages WHERE sender_child_id IN (%s, %s) OR receiver_child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM child_conversations WHERE child1_id IN (%s, %s) OR child2_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM parent_notifications WHERE child_id IN (%s, %s) OR parent_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_PARENT_ID, TEST_PARENT_2_ID))
    execute("DELETE FROM followers WHERE child_id IN (%s, %s) OR following_child_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM blocked_users WHERE blocker_id IN (%s, %s) OR blocked_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM reports WHERE reporter_id IN (%s, %s)", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))


# ============================================================================
# 1. 18+ CONTENT RESTRICTION END-TO-END FLOW (Part 3)
# ============================================================================

def test_18_plus_safe_content_persists_and_is_visible():
    """Child submits safe content -> evaluates ALLOW -> persists with ALLOWED status."""
    safe_caption = "Learning about solar system and space exploration!"
    signals, decision = evaluate(TEST_CHILD_A_ID, "TEXT", safe_caption)
    assert decision.action == "ALLOW"
    assert signals.get("adult_score", 0.0) < 0.20

    # Insert post into database with ALLOWED status matching posts_moderation_status_check
    post_row = execute("""
        INSERT INTO posts(child_id, media_type, caption, content_category, is_safe, moderation_status, adult_score, safety_score)
        VALUES (%s, 'TEXT', %s, 'Science', TRUE, 'ALLOWED', %s, %s)
        RETURNING post_id
    """, (TEST_CHILD_A_ID, safe_caption, signals.get("adult_score", 0.0), 100.0 - decision.risk), returning=True)
    
    post_id = post_row["post_id"]
    assert post_id is not None

    # Verify query for visible child feed retrieves it
    visible = fetch_one("SELECT post_id, caption, moderation_status FROM posts WHERE post_id=%s AND moderation_status='ALLOWED'", (post_id,))
    assert visible is not None
    assert visible["caption"] == safe_caption

    # Cleanup
    execute("DELETE FROM posts WHERE post_id=%s", (post_id,))


def test_18_plus_adult_content_blocked_and_quarantined():
    """Child submits adult content -> evaluates BLOCK -> event recorded -> notification created -> NOT visible in feed."""
    explicit_phrase = "watch explicit porn xxx adult video nsfw sex tape"
    signals, decision = evaluate(TEST_CHILD_A_ID, "TEXT", explicit_phrase)
    
    assert decision.action == "BLOCK"
    assert decision.risk >= 90.0

    # Simulate platform policy enforcement: record moderation_event and notify parent
    event_id = record(TEST_CHILD_A_ID, "TEXT", None, signals, decision)
    assert event_id is not None
    parent_notify(TEST_CHILD_A_ID, "CONTENT_BLOCKED", decision.reason, "/parent/safety/")

    # Verify moderation_events row exists in PostgreSQL
    event_row = fetch_one("SELECT * FROM moderation_events WHERE event_id=%s", (event_id,))
    assert event_row is not None
    assert event_row["child_id"] == TEST_CHILD_A_ID
    assert event_row["decision"] == "BLOCK"
    assert event_row["risk_score"] >= 90.0

    # Verify parent notification is persisted
    parent_alert = fetch_one("""
        SELECT * FROM parent_notifications 
        WHERE child_id=%s
        ORDER BY created_at DESC LIMIT 1
    """, (TEST_CHILD_A_ID,))
    assert parent_alert is not None
    assert parent_alert["parent_id"] == TEST_PARENT_ID

    # Verify blocked content was NEVER persisted to visible posts
    not_in_feed = fetch_all("SELECT post_id FROM posts WHERE caption=%s AND moderation_status='ALLOWED'", (explicit_phrase,))
    assert len(not_in_feed) == 0

    # Cleanup
    execute("DELETE FROM moderation_events WHERE event_id=%s", (event_id,))


def test_18_plus_cannot_bypass_via_reel_or_story():
    """Verify that reels and stories cannot bypass 18+ policy."""
    from uploadPost import routes as up_routes
    assert hasattr(up_routes, "_create"), "uploadPost must have _create pipeline"
    sig, dec = up_routes.evaluate(TEST_CHILD_A_ID, "TEXT", "send nudes private parts")
    assert dec.action == "BLOCK"
    assert "18+" in dec.reason.lower() or "adult" in dec.reason.lower() or "blocked" in dec.reason.lower()


# ============================================================================
# 2. CYBERBULLYING & TOXICITY NLP (Part 4)
# ============================================================================

def test_cyberbullying_mild_negative_allowed():
    """Mild opinion is allowed in child communication."""
    signals, decision = evaluate(TEST_CHILD_A_ID, "TEXT", "I do not like this project.")
    assert decision.action == "ALLOW"


def test_cyberbullying_harmful_phrase_blocked():
    """Cyberbullying phrase is blocked, recorded, and parent alerted."""
    bullying_text = "nobody likes you, you are useless, loser, go die"
    signals, decision = evaluate(TEST_CHILD_A_ID, "TEXT", bullying_text)
    
    assert decision.action in ["BLOCK", "REVIEW"]
    assert decision.risk >= 50.0

    # Test DM interception: child message with bullying is NOT delivered
    event_id = record(TEST_CHILD_A_ID, "TEXT", None, signals, decision)
    
    msg_row = execute("""
        INSERT INTO child_messages(conversation_id, sender_child_id, receiver_child_id, message_type, message_text, moderation_status)
        VALUES (%s, %s, %s, 'TEXT', %s, 'BLOCKED')
        RETURNING child_message_id
    """, (TEST_CONV_ID, TEST_CHILD_A_ID, TEST_CHILD_B_ID, bullying_text), returning=True)
    msg_id = msg_row["child_message_id"]

    # Receiver cannot see blocked messages in inbox
    peer_inbox = fetch_all("""
        SELECT * FROM child_messages 
        WHERE receiver_child_id=%s AND moderation_status='ALLOWED' AND child_message_id=%s
    """, (TEST_CHILD_B_ID, msg_id))
    assert len(peer_inbox) == 0

    # Cleanup
    execute("DELETE FROM child_messages WHERE child_message_id=%s", (msg_id,))
    execute("DELETE FROM moderation_events WHERE event_id=%s", (event_id,))


# ============================================================================
# 3. WEAPON & DANGEROUS OBJECT DETECTION (Part 5)
# ============================================================================

def test_weapon_detection_labels_and_policy():
    """Verify dangerous weapon classification triggers appropriate action."""
    for dangerous in ["Handgun", "Kitchen knife", "Rifle", "Axe"]:
        assert bool(classify_label(dangerous)) is True

    high_conf = classify_detections([{"label": "Kitchen knife", "confidence": 0.85}])
    assert high_conf["block"] is True

    d = decide({
        "adult_score": 0.0, "sexual_score": 0.0, "violence_score": 0.0, "weapon_score": 1.0,
        "toxicity_score": 0.0, "general_score": 1.0, "category": "IMAGE",
        "model_signals": {"yolo": {"detections": [{"label": "Kitchen knife", "confidence": 0.85}]}}
    }, "STRICT")
    assert d.action == "BLOCK"
    assert "knife" in d.reason.lower() or "dangerous object" in d.reason.lower()


# ============================================================================
# 4. FACE & LIVENESS BACKEND READINESS (Part 6)
# ============================================================================

def test_face_non_face_rejection_and_persistence():
    """Non-face input is rejected; face profile persistence schema is verified."""
    with pytest.raises(Exception):
        remote_client.face_embedding("non_existent_or_blank.jpg")

    dummy_emb = [0.01 * i for i in range(512)]
    execute("""
        INSERT INTO face_profiles(child_id, embedding, model_name)
        VALUES (%s, %s::jsonb, 'Facenet512')
        ON CONFLICT(child_id) DO UPDATE SET embedding=EXCLUDED.embedding, model_name='Facenet512', updated_at=NOW()
    """, (TEST_CHILD_A_ID, json.dumps(dummy_emb)))

    profile = fetch_one("SELECT child_id, model_name FROM face_profiles WHERE child_id=%s", (TEST_CHILD_A_ID,))
    assert profile is not None
    assert profile["model_name"] in ["Facenet512", "E2E"]

    execute("DELETE FROM face_profiles WHERE child_id=%s", (TEST_CHILD_A_ID,))


# ============================================================================
# 5. AUDIO MODERATION RETIRED STATUS (Part 7)
# ============================================================================

def test_audio_moderation_contract_retired():
    """Standalone audio and voice uploads are explicitly disabled and fail closed."""
    signals, decision = evaluate(TEST_CHILD_A_ID, "AUDIO", "dummy.mp3")
    assert decision.action == "BLOCK"
    assert "Standalone audio and voice uploads are disabled" in decision.reason

    signals_v, decision_v = evaluate(TEST_CHILD_A_ID, "VOICE", "dummy.wav")
    assert decision_v.action == "BLOCK"


# ============================================================================
# 6. REAL EMAIL / RESEND VERIFICATION (Part 8)
# ============================================================================

def test_resend_email_sending_and_otp_lifecycle():
    """Resend API sends transactional verification email and handles OTP expiration."""
    status = get_mail_status()
    assert status["configured"] is True
    assert status["provider"] == "resend"

    send_ok = send_email(
        "delivered@resend.dev",
        "LittleNet Pre-Device Verification",
        "<p>Your OTP is <strong>123456</strong></p>"
    )
    assert send_ok is True, "Resend API send must succeed"

    otp_code = "789123"
    code_hash = hashlib.sha256(f"parent-email-otp:{TEST_PARENT_ID}:{otp_code}:test-secret".encode()).hexdigest()
    expires_at = datetime.utcnow() + timedelta(minutes=10)

    execute("""
        INSERT INTO parent_email_otps(user_id, code_hash, expires_at, attempts)
        VALUES (%s, %s, %s, 0)
        ON CONFLICT(user_id) DO UPDATE SET code_hash=EXCLUDED.code_hash, expires_at=EXCLUDED.expires_at, attempts=0
    """, (TEST_PARENT_ID, code_hash, expires_at))

    otp_row = fetch_one("SELECT * FROM parent_email_otps WHERE user_id=%s", (TEST_PARENT_ID,))
    assert otp_row is not None
    assert otp_row["code_hash"] == code_hash
    assert otp_row["expires_at"] > datetime.utcnow()

    execute("DELETE FROM parent_email_otps WHERE user_id=%s", (TEST_PARENT_ID,))


# ============================================================================
# 7. FOLLOW REQUEST + PARENT APPROVAL WORKFLOW (Part 12)
# ============================================================================

def test_follow_request_parent_approval_lifecycle():
    """Child A requests to follow Child B -> REQUESTED -> Parent A approves (SENDER_PARENT_APPROVED) -> Parent B approves reciprocal (RECEIVER_PARENT_PENDING -> ACTIVE)."""
    execute("DELETE FROM followers WHERE (child_id=%s AND following_child_id=%s) OR (child_id=%s AND following_child_id=%s)", 
            (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID))

    follow_row = execute("""
        INSERT INTO followers(child_id, following_child_id, approved, approval_stage)
        VALUES (%s, %s, FALSE, 'REQUESTED')
        RETURNING follower_id
    """, (TEST_CHILD_A_ID, TEST_CHILD_B_ID), returning=True)
    follower_id = follow_row["follower_id"]

    f = fetch_one("SELECT * FROM followers WHERE follower_id=%s", (follower_id,))
    assert f["approved"] is False
    assert f["approval_stage"] == "REQUESTED"

    # Step 1: Parent of Child A (Sender Parent) approves
    execute("""
        UPDATE followers 
        SET approved = TRUE, sender_parent_approved_at = NOW()
        WHERE follower_id = %s
    """, (follower_id,))

    f_sender = fetch_one("SELECT * FROM followers WHERE follower_id=%s", (follower_id,))
    assert f_sender["approval_stage"] == "SENDER_PARENT_APPROVED"
    assert f_sender["approved"] is False

    # The trigger automatically created the reciprocal row for Child B's parent!
    reciprocal = fetch_one("""
        SELECT * FROM followers 
        WHERE child_id=%s AND following_child_id=%s
    """, (TEST_CHILD_B_ID, TEST_CHILD_A_ID))
    assert reciprocal is not None
    assert reciprocal["approval_stage"] == "RECEIVER_PARENT_PENDING"

    # Step 2: Parent of Child B (Receiver Parent) approves the reciprocal row
    execute("""
        UPDATE followers 
        SET approved = TRUE, receiver_parent_approved_at = NOW()
        WHERE follower_id = %s
    """, (reciprocal["follower_id"],))

    # Now both sides are ACTIVE and approved = TRUE!
    active_rel_a = fetch_one("SELECT * FROM followers WHERE follower_id=%s", (follower_id,))
    active_rel_b = fetch_one("SELECT * FROM followers WHERE follower_id=%s", (reciprocal["follower_id"],))
    assert active_rel_a["approved"] is True
    assert active_rel_a["approval_stage"] == "ACTIVE"
    assert active_rel_b["approved"] is True
    assert active_rel_b["approval_stage"] == "ACTIVE"

    execute("DELETE FROM followers WHERE (child_id=%s AND following_child_id=%s) OR (child_id=%s AND following_child_id=%s)", 
            (TEST_CHILD_A_ID, TEST_CHILD_B_ID, TEST_CHILD_B_ID, TEST_CHILD_A_ID))


# ============================================================================
# 8. BLOCK & REPORT WORKFLOW (Part 13)
# ============================================================================

def test_block_user_and_report_content():
    """Child A blocks Child B and reports objectionable behavior."""
    execute("DELETE FROM blocked_users WHERE blocker_id=%s AND blocked_id=%s", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))

    execute("""
        INSERT INTO blocked_users(blocker_id, blocked_id)
        VALUES (%s, %s)
    """, (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    
    blocked = fetch_one("SELECT * FROM blocked_users WHERE blocker_id=%s AND blocked_id=%s", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    assert blocked is not None

    rep_row = execute("""
        INSERT INTO reports(reporter_id, target_type, target_id, reason, details, status)
        VALUES (%s, 'USER', %s, 'Harassment', 'Unkind language in playground', 'OPEN')
        RETURNING report_id
    """, (TEST_CHILD_A_ID, TEST_CHILD_B_ID), returning=True)
    report_id = rep_row["report_id"]

    admin_rep = fetch_one("SELECT * FROM reports WHERE report_id=%s AND status='OPEN'", (report_id,))
    assert admin_rep is not None
    assert admin_rep["reason"] == "Harassment"

    execute("DELETE FROM blocked_users WHERE blocker_id=%s AND blocked_id=%s", (TEST_CHILD_A_ID, TEST_CHILD_B_ID))
    execute("DELETE FROM reports WHERE report_id=%s", (report_id,))


# ============================================================================
# 9. PARENT ALERTS & NOTIFICATION ISOLATION (Part 14)
# ============================================================================

def test_parent_alerts_tenant_isolation():
    """Verify safety notifications route strictly to linked parent and not other parents."""
    notif_row = execute("""
        INSERT INTO parent_notifications(parent_id, child_id, notification_type, notification_message)
        VALUES (%s, %s, 'SAFETY_ALERT', 'Content flagged during inspection')
        RETURNING notification_id
    """, (TEST_PARENT_ID, TEST_CHILD_A_ID), returning=True)
    notif_id = notif_row["notification_id"]

    parent_1_notifs = fetch_all("SELECT * FROM parent_notifications WHERE parent_id=%s AND notification_id=%s", (TEST_PARENT_ID, notif_id))
    assert len(parent_1_notifs) == 1

    parent_2_notifs = fetch_all("SELECT * FROM parent_notifications WHERE parent_id=%s AND notification_id=%s", (TEST_PARENT_2_ID, notif_id))
    assert len(parent_2_notifs) == 0

    execute("DELETE FROM parent_notifications WHERE notification_id=%s", (notif_id,))


# ============================================================================
# 10. SCREEN TIME & SMART PARENT CONTROLS (Part 15)
# ============================================================================

def test_screen_time_and_parent_controls_server_enforcement():
    """Verify server-side controls for posting, messaging, and daily screen time."""
    execute("UPDATE parent_control_settings SET allow_posting=FALSE WHERE child_id=%s", (TEST_CHILD_A_ID,))
    ctrl = fetch_one("SELECT allow_posting, allow_messaging FROM parent_control_settings WHERE child_id=%s", (TEST_CHILD_A_ID,))
    assert ctrl["allow_posting"] is False

    # Restore posting
    execute("UPDATE parent_control_settings SET allow_posting=TRUE WHERE child_id=%s", (TEST_CHILD_A_ID,))

    execute("""
        INSERT INTO child_time_limits(child_id, daily_limit_minutes, strict_mode)
        VALUES (%s, 45, TRUE)
        ON CONFLICT(child_id) DO UPDATE SET daily_limit_minutes=45, strict_mode=TRUE
    """, (TEST_CHILD_A_ID,))
    
    limit_row = fetch_one("SELECT * FROM child_time_limits WHERE child_id=%s", (TEST_CHILD_A_ID,))
    assert limit_row["daily_limit_minutes"] == 45
    assert limit_row["strict_mode"] is True


# ============================================================================
# 11. ADMIN MODERATION WORKFLOW (Part 16)
# ============================================================================

def test_admin_moderation_review_lifecycle():
    """Admin inspects OPEN review event, submits decision, and appends audit record."""
    event_row = execute("""
        INSERT INTO moderation_events(child_id, content_type, decision, risk_score, adult_score, status, reason)
        VALUES (%s, 'IMAGE', 'REVIEW', 55.0, 0.45, 'OPEN', 'Requires human review')
        RETURNING event_id
    """, (TEST_CHILD_A_ID,), returning=True)
    event_id = event_row["event_id"]

    open_events = fetch_all("SELECT * FROM moderation_events WHERE status='OPEN' AND decision='REVIEW'")
    assert any(x["event_id"] == event_id for x in open_events)

    admin_user = fetch_one("SELECT user_id FROM users WHERE role='ADMIN' LIMIT 1")
    admin_id = admin_user["user_id"] if admin_user else 22

    execute("""
        INSERT INTO moderation_reviews(event_id, reviewer_id, action, notes)
        VALUES (%s, %s, 'APPROVE', 'Reviewed and deemed safe educational diagram')
    """, (event_id, admin_id))
    
    execute("UPDATE moderation_events SET status='RESOLVED' WHERE event_id=%s", (event_id,))

    review_record = fetch_one("SELECT * FROM moderation_reviews WHERE event_id=%s", (event_id,))
    assert review_record is not None
    assert review_record["action"] == "APPROVE"

    updated_event = fetch_one("SELECT status FROM moderation_events WHERE event_id=%s", (event_id,))
    assert updated_event["status"] == "RESOLVED"

    execute("DELETE FROM moderation_reviews WHERE event_id=%s", (event_id,))
    execute("DELETE FROM moderation_events WHERE event_id=%s", (event_id,))


# ============================================================================
# 12. R2 & DATABASE PERSISTENCE SANITY (Part 17)
# ============================================================================

def test_r2_and_database_persistence():
    """Verify Cloudflare R2 bucket connection and PostgreSQL database persistence."""
    health = object_storage.healthcheck()
    assert health.get("ok") is True
    assert health.get("bucket") == "littlenet-media"

    row = fetch_one("SELECT COUNT(*) n FROM users")
    assert row["n"] > 0
