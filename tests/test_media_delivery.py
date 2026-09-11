"""Tests for LittleNet secure direct media delivery service."""
from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

import pytest

from services.media_delivery import resolve_media_delivery


def test_media_delivery_denies_empty_reference():
    res = resolve_media_delivery(None)
    assert res["delivery_mode"] == "DENIED"
    assert res["url"] is None

    res2 = resolve_media_delivery("")
    assert res2["delivery_mode"] == "DENIED"
    assert res2["url"] is None


def test_media_delivery_handles_public_and_static_urls():
    res = resolve_media_delivery("https://cdn.example.com/asset.mp4")
    assert res["delivery_mode"] == "DIRECT_PUBLIC"
    assert res["url"] == "https://cdn.example.com/asset.mp4"

    res_static = resolve_media_delivery("static/icons/app_logo.png")
    assert res_static["delivery_mode"] == "DIRECT_STATIC"
    assert "static/icons/app_logo.png" in res_static["url"]


def test_media_delivery_local_file_fallback():
    res = resolve_media_delivery("uploads/profile_pictures/avatar.jpg")
    assert res["delivery_mode"] == "PROXY_FALLBACK"
    assert "/api/mobile/v1/media?ref=" in res["url"]


def test_media_delivery_unauthorized_r2_denied():
    r2_ref = "uploads/r2/posts/10/secret_video.mp4"

    with patch("services.media_delivery.r2_enabled", return_value=True), \
         patch("services.media_delivery.is_authorized_viewer", return_value=False):
        res = resolve_media_delivery(r2_ref, viewer_id=99, viewer_role="CHILD")
        # Fail closed: unauthorized viewers must NEVER obtain a signed URL
        assert res["delivery_mode"] == "DENIED"
        assert res["url"] is None
        assert res["expires_at"] is None


def test_media_delivery_authorized_r2_generates_signed_url():
    r2_ref = "uploads/r2/reels/1/safe_learning.mp4"
    mock_signed_url = "https://bucket.r2.cloudflarestorage.com/reels/1/safe_learning.mp4?X-Amz-Signature=abc123"

    with patch("services.media_delivery.r2_enabled", return_value=True), \
         patch("services.media_delivery.is_authorized_viewer", return_value=True), \
         patch("services.media_delivery.signed_download_url", return_value=mock_signed_url) as mock_sign:
        res = resolve_media_delivery(r2_ref, viewer_id=5, viewer_role="CHILD", expires_seconds=600)
        assert res["delivery_mode"] == "DIRECT_SIGNED"
        assert res["url"] == mock_signed_url
        assert res["expires_at"] is not None
        mock_sign.assert_called_once_with(r2_ref, expires_seconds=600)


def test_media_delivery_fallback_when_r2_disabled():
    r2_ref = "uploads/r2/posts/1/video.mp4"
    with patch("services.media_delivery.r2_enabled", return_value=False):
        res = resolve_media_delivery(r2_ref, viewer_id=5, viewer_role="CHILD")
        assert res["delivery_mode"] == "PROXY_FALLBACK"
        assert "/api/mobile/v1/media?ref=" in res["url"]
