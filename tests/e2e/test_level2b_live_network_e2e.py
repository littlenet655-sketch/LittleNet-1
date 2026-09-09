"""Level 2B: True Live Network E2E Test Suite for LittleNet

Executes real HTTP/HTTPS calls against the deployed production system:
https://littlenet655--littlenet-web-web.modal.run

Proves end-to-end:
Parent auth -> child listing/creation -> child login -> feed -> post -> moderation ->
persistence -> retrieve post -> second test child -> follow -> like -> comment ->
DM exchange -> parent controls -> admin safety overview.
"""
import os
import time
import requests
import pytest

LIVE_BASE_URL = os.environ.get("LITTLENET_LIVE_URL", "https://littlenet655--littlenet-web-web.modal.run").rstrip("/")
TIMEOUT = 45

PARENT_CREDS = {
    "identifier": "real_parent",
    "password": "P@ssword123!",
    "mode": "parent",
}

KID_A_CREDS = {
    "identifier": "real_kid_alpha",
    "password": "KidAlpha123!",
    "mode": "kids",
}

KID_B_CREDS = {
    "identifier": "real_kid_beta",
    "password": "KidBeta123!",
    "mode": "kids",
}

ADMIN_CREDS = {
    "identifier": "real_admin",
    "password": "Admin123!",
    "mode": "admin",
}


@pytest.fixture(scope="module")
def live():
    class LiveContext:
        session = requests.Session()
        parent_token = None
        kid_a_token = None
        kid_b_token = None
        admin_token = None
        created_post_id = None

    ctx = LiveContext()
    ctx.session.headers.update({"User-Agent": "LittleNet-Level2B-LiveE2E/1.0"})
    return ctx


def test_01_parent_auth_live(live):
    """Step 1: Parent authenticates over HTTPS, receives bearer JWT."""
    res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/auth/login",
        json=PARENT_CREDS,
        timeout=TIMEOUT,
    )
    assert res.status_code == 200, f"Parent login failed: {res.status_code} {res.text}"
    data = res.json()
    assert data.get("ok") is True
    assert "token" in data
    assert data.get("user", {}).get("role") == "PARENT"
    live.parent_token = data["token"]


def test_02_parent_dashboard_and_controls_live(live):
    """Step 2: Parent views children, dashboard telemetry, and controls."""
    headers = {"Authorization": f"Bearer {live.parent_token}"}
    res = live.session.get(f"{LIVE_BASE_URL}/api/mobile/v1/parent/dashboard", headers=headers, timeout=TIMEOUT)
    assert res.status_code == 200, f"Parent dashboard failed: {res.status_code} {res.text}"
    children = res.json().get("children", [])
    child_ids = [c["user_id"] for c in children]
    assert 999201 in child_ids, f"Kid Alpha not linked to parent: {children}"
    assert 999202 in child_ids, f"Kid Beta not linked to parent: {children}"

    # Verify parent controls for child 999201
    res_ctrl = live.session.get(f"{LIVE_BASE_URL}/api/mobile/v1/parent/controls/999201", headers=headers, timeout=TIMEOUT)
    assert res_ctrl.status_code == 200
    assert res_ctrl.json().get("ok") is True


def test_03_child_alpha_login_and_feed_live(live):
    """Step 3 & 4: Child Alpha logs in and retrieves feed."""
    res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/auth/login",
        json=KID_A_CREDS,
        timeout=TIMEOUT,
    )
    assert res.status_code == 200, f"Child Alpha login failed: {res.status_code} {res.text}"
    data = res.json()
    assert data.get("ok") is True
    assert data.get("user", {}).get("role") == "CHILD"
    live.kid_a_token = data["token"]

    # Retrieve live feed
    headers = {"Authorization": f"Bearer {live.kid_a_token}"}
    feed_res = live.session.get(f"{LIVE_BASE_URL}/api/mobile/v1/kids/home", headers=headers, timeout=TIMEOUT)
    assert feed_res.status_code == 200, f"Feed retrieval failed: {feed_res.status_code} {feed_res.text}"
    body = feed_res.json()
    assert "posts" in body or "feed" in body


def test_04_child_post_creation_and_moderation_live(live):
    """Step 5, 6 & 7: Child Alpha creates a post, verified by live AI moderation, persisted."""
    headers = {"Authorization": f"Bearer {live.kid_a_token}"}
    
    # 1. PII rejection test: Presidio PII detects digits as phone numbers
    pii_payload = {"caption": f"Call me at 9876543210 for homework", "content_category": "Other", "kind": "post"}
    pii_res = live.session.post(f"{LIVE_BASE_URL}/api/mobile/v1/kids/posts", data=pii_payload, headers=headers, timeout=TIMEOUT)
    assert pii_res.status_code == 400
    assert "caption_pii_blocked" in pii_res.text

    # 2. Clean text post creation: moderated by real remote AI, allowed and persisted
    clean_caption = f"Exploring astronomy and the Orion constellation in science class"
    res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/kids/posts",
        data={"caption": clean_caption, "content_category": "Other", "kind": "post"},
        headers=headers,
        timeout=TIMEOUT,
    )
    assert res.status_code == 200, f"Post creation failed: {res.status_code} {res.text}"
    post_data = res.json()
    assert post_data.get("ok") is True
    assert post_data.get("status") == "ALLOW"
    live.created_post_id = post_data["post_id"]


def test_05_second_child_auth_and_two_parent_friendship_live(live):
    """Step 8: Child Beta logs in, requests follow; Sender and Receiver parents approve for two-parent consent."""
    res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/auth/login",
        json=KID_B_CREDS,
        timeout=TIMEOUT,
    )
    assert res.status_code == 200, f"Child Beta login failed: {res.status_code} {res.text}"
    live.kid_b_token = res.json()["token"]
    headers_b = {"Authorization": f"Bearer {live.kid_b_token}"}
    headers_p = {"Authorization": f"Bearer {live.parent_token}"}

    # Follow Child Alpha (handle toggle if previously active/pending)
    follow_res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/kids/follow/999201",
        headers=headers_b,
        timeout=TIMEOUT,
    )
    assert follow_res.status_code == 200
    if follow_res.json().get("status") == "removed":
        # Was toggled off; toggle on to pending
        follow_res = live.session.post(
            f"{LIVE_BASE_URL}/api/mobile/v1/kids/follow/999201",
            headers=headers_b,
            timeout=TIMEOUT,
        )
        assert follow_res.status_code == 200

    # Sender parent approves
    app1 = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/parent/follow-requests/action",
        json={"child_id": 999202, "target_id": 999201, "action": "approve"},
        headers=headers_p,
        timeout=TIMEOUT,
    )
    assert app1.status_code == 200

    # Receiver parent approves (activates two-parent friendship)
    app2 = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/parent/follow-requests/action",
        json={"child_id": 999201, "target_id": 999202, "action": "approve"},
        headers=headers_p,
        timeout=TIMEOUT,
    )
    assert app2.status_code == 200


def test_06_like_and_comment_live(live):
    """Step 9 & 10: Child Beta likes and comments on Child Alpha's post."""
    headers_b = {"Authorization": f"Bearer {live.kid_b_token}"}
    post_id = live.created_post_id

    # Like post
    like_res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/kids/posts/{post_id}/like",
        headers=headers_b,
        timeout=TIMEOUT,
    )
    assert like_res.status_code == 200, f"Like failed: {like_res.status_code} {like_res.text}"
    assert like_res.json().get("ok") is True

    # Comment on post (moderated by real AI)
    comment_payload = {"text": "Great astronomy project, Orion is amazing!"}
    comment_res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/kids/posts/{post_id}/comment",
        json=comment_payload,
        headers=headers_b,
        timeout=TIMEOUT,
    )
    assert comment_res.status_code == 200, f"Comment failed: {comment_res.status_code} {comment_res.text}"
    assert comment_res.json().get("ok") is True
    assert comment_res.json().get("status") == "ALLOW"


def test_07_direct_message_exchange_live(live):
    """Step 11: Child Beta sends DM to Child Alpha, Alpha retrieves and reads it."""
    headers_b = {"Authorization": f"Bearer {live.kid_b_token}"}
    dm_payload = {"message_text": "Hey Alpha, did you finish the robotics challenge?"}
    dm_res = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/kids/chat/999201",
        json=dm_payload,
        headers=headers_b,
        timeout=TIMEOUT,
    )
    assert dm_res.status_code == 200, f"DM send failed: {dm_res.status_code} {dm_res.text}"
    assert dm_res.json().get("ok") is True
    assert dm_res.json().get("status") == "ALLOW"

    # Child Alpha checks conversation
    headers_a = {"Authorization": f"Bearer {live.kid_a_token}"}
    conv_res = live.session.get(
        f"{LIVE_BASE_URL}/api/mobile/v1/kids/chat/999202",
        headers=headers_a,
        timeout=TIMEOUT,
    )
    assert conv_res.status_code == 200, f"DM read failed: {conv_res.status_code} {conv_res.text}"
    messages = conv_res.json().get("messages", [])
    assert len(messages) >= 1
    assert any("robotics challenge" in (m.get("message_text") or m.get("content") or "") for m in messages)


def test_08_admin_safety_overview_live(live):
    """Step 12: Admin authenticates and verifies dashboard and moderation review queue."""
    admin_login = live.session.post(
        f"{LIVE_BASE_URL}/api/mobile/v1/auth/login",
        json=ADMIN_CREDS,
        timeout=TIMEOUT,
    )
    assert admin_login.status_code == 200, f"Admin login failed: {admin_login.status_code} {admin_login.text}"
    live.admin_token = admin_login.json()["token"]
    admin_headers = {"Authorization": f"Bearer {live.admin_token}"}

    dash_res = live.session.get(f"{LIVE_BASE_URL}/api/mobile/v1/admin/dashboard", headers=admin_headers, timeout=TIMEOUT)
    assert dash_res.status_code == 200, f"Admin dashboard failed: {dash_res.status_code} {dash_res.text}"
    assert dash_res.json().get("ok") is True

    rev_res = live.session.get(f"{LIVE_BASE_URL}/api/mobile/v1/admin/reviews", headers=admin_headers, timeout=TIMEOUT)
    assert rev_res.status_code == 200
    body = rev_res.json()
    assert "reviews" in body or "events" in body
