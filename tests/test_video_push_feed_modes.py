"""Tests for video delivery abstraction, push notifications, feed modes, and story views."""
from __future__ import annotations

import json
from unittest.mock import MagicMock, patch
import pytest

from services.curated_feed import get_feed_page
from services.push_notifications import (
    get_active_tokens_for_user,
    notify_child_content_status,
    notify_parent_safety_event,
    register_device_token,
    revoke_device_token,
    send_expo_push,
)
from services.video_delivery import (
    CloudflareStreamDeliveryProvider,
    SanitizedMP4DeliveryProvider,
    get_video_provider,
    probe_video_metadata,
    resolve_video_playback,
)


def test_probe_video_metadata_fallback():
    meta = probe_video_metadata("non_existent_file.mp4")
    assert meta["duration_ms"] == 15000
    assert meta["width"] == 1080
    assert meta["height"] == 1920
    assert meta["aspect_ratio"] == "9:16"


def test_video_delivery_provider_selection(monkeypatch):
    monkeypatch.delenv("CLOUDFLARE_STREAM_ACCOUNT_ID", raising=False)
    monkeypatch.delenv("CLOUDFLARE_STREAM_API_TOKEN", raising=False)
    p = get_video_provider()
    assert isinstance(p, SanitizedMP4DeliveryProvider)
    assert p.provider_name == "R2_SANITIZED_MP4"

    monkeypatch.setenv("CLOUDFLARE_STREAM_ACCOUNT_ID", "acc_123")
    monkeypatch.setenv("CLOUDFLARE_STREAM_API_TOKEN", "tok_abc")
    p2 = get_video_provider()
    assert isinstance(p2, CloudflareStreamDeliveryProvider)
    assert p2.provider_name == "CLOUDFLARE_STREAM"


def test_sanitized_mp4_playback_authorized():
    asset = {
        "media_id": 99,
        "post_id": 101,
        "published_reference": "uploads/r2/reels/1/clean.mp4",
        "poster_reference": "uploads/r2/reels/1/poster.jpg",
        "provider": "R2_SANITIZED_MP4",
        "playback_id": "play_101",
        "duration_ms": 12000,
        "width": 1080,
        "height": 1920,
        "aspect_ratio": "9:16",
    }
    provider = SanitizedMP4DeliveryProvider()
    with patch("services.video_delivery.resolve_media_delivery", return_value={"url": "https://signed.r2/clean.mp4", "delivery_mode": "DIRECT_SIGNED", "expires_at": 1700000600}):
        res = provider.get_playback_info(asset, viewer_id=1, viewer_role="CHILD")
        assert res["playback_url"] == "https://signed.r2/clean.mp4"
        assert res["delivery_type"] == "MP4"
        assert res["duration_ms"] == 12000
        assert res["aspect_ratio"] == "9:16"


def test_cloudflare_stream_playback_fail_closed_unauthorized():
    asset = {
        "media_id": 99,
        "post_id": 101,
        "published_reference": "uploads/r2/reels/1/clean.mp4",
        "playback_id": "cfs_101",
    }
    provider = CloudflareStreamDeliveryProvider()
    with patch("services.video_delivery.is_authorized_viewer", return_value=False):
        res = provider.get_playback_info(asset, viewer_id=2, viewer_role="CHILD")
        assert res["playback_url"] is None
        assert res["delivery_mode"] == "DENIED"


def test_push_notifications_privacy_filter():
    sent_payloads = []

    def mock_urlopen(req, timeout=None):
        data = json.loads(req.data.decode("utf-8"))
        sent_payloads.extend(data)
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({"data": [{"status": "ok"}]}).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        return mock_resp

    with patch("urllib.request.urlopen", side_effect=mock_urlopen):
        tokens = ["ExponentPushToken[abc123xyz]"]
        leaky_data = {
            "postId": 42,
            "password": "supersecretpassword",
            "embedding": [0.1, 0.2, 0.3],
            "raw_text": "Private text",
            "safe_tag": "notification",
        }
        ok = send_expo_push(tokens, title="Test", body="Hello", data=leaky_data)
        assert ok is True
        assert len(sent_payloads) == 1
        msg = sent_payloads[0]
        # Ensure private/sensitive keys were stripped
        assert "password" not in msg["data"]
        assert "embedding" not in msg["data"]
        assert "raw_text" not in msg["data"]
        assert msg["data"]["postId"] == 42
        assert msg["data"]["safe_tag"] == "notification"


def test_feed_modes_server_filtering():
    sample_session_items = [
        {"source_type": "SOCIAL", "source_id": 1, "category": "General", "moderation_status": "ALLOWED"},
        {"source_type": "CURATED", "source_id": 10, "category": "Science", "moderation_status": "ALLOWED"},
        {"source_type": "SOCIAL", "source_id": 2, "category": "Art", "moderation_status": "ALLOWED"},
        {"source_type": "CURATED", "source_id": 20, "category": "Math", "moderation_status": "ALLOWED"},
    ]

    with patch("services.curated_feed.get_or_create_feed_session", return_value=("sess-123", sample_session_items)):
        # For You: all items
        page_all = get_feed_page(child_id=1, surface="FEED", mode="for_you")
        assert len(page_all["items"]) == 4

        # Friends: only SOCIAL items
        page_friends = get_feed_page(child_id=1, surface="FEED", mode="friends")
        assert len(page_friends["items"]) == 2
        assert all(it["source_type"] == "SOCIAL" for it in page_friends["items"])

        # Learn: only CURATED or educational items
        page_learn = get_feed_page(child_id=1, surface="FEED", mode="learn")
        assert len(page_learn["items"]) == 3  # 2 curated + 1 art social
        assert all(it["source_type"] == "CURATED" or it["category"] in {"Science", "Math", "Art"} for it in page_learn["items"])
