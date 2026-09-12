"""Secure Direct Media Delivery Service for LittleNet.

Provides an abstraction for resolving media delivery URLs for posts, reels,
avatars, and curated educational assets.

When Cloudflare R2 is configured and the requesting viewer is authorized under
LittleNet's child safety and parental controls, this service generates a short-lived
(5-15 minute) signed R2/CDN download URL bound to the exact object key.

If R2 is unconfigured, or if the media is a local/ephemeral asset, or if the viewer
context is not provided, it falls back to the existing authenticated
/api/mobile/v1/media proxy endpoint.

Security invariants:
- Never generates permanent public R2 URLs.
- Never makes the R2 bucket public.
- Preserves LittleNet visibility, parent-control, and child-age restrictions.
- Unauthorized users NEVER obtain a signed URL.
"""
from __future__ import annotations

import time
from typing import Any, Optional
from urllib.parse import quote

from config import Config
from services.object_storage import (
    R2_REFERENCE_PREFIX,
    enabled as r2_enabled,
    is_reference as is_r2_reference,
    signed_download_url,
)

DEFAULT_SIGNED_URL_TTL = 600  # 10 minutes (between 5 and 15 minutes)


def is_authorized_viewer(viewer_id: int | None, viewer_role: str | None, reference: str) -> bool:
    """Validate that the requesting viewer has explicit access to this media item."""
    if not viewer_id or not viewer_role:
        return False
    try:
        from mobile.api import _media_allowed

        return bool(_media_allowed(int(viewer_id), str(viewer_role).upper(), reference))
    except Exception:
        return False


def resolve_media_delivery(
    reference: str | None,
    viewer_id: int | None = None,
    viewer_role: str | None = None,
    expires_seconds: int = DEFAULT_SIGNED_URL_TTL,
) -> dict[str, Any]:
    """Resolve a media reference into an authorized delivery payload.

    Returns:
        {
            "url": str | None,
            "delivery_mode": "DIRECT_SIGNED" | "DIRECT_STATIC" | "DIRECT_PUBLIC" | "PROXY_FALLBACK" | "DENIED",
            "expires_at": int | None,
        }
    """
    if not reference:
        return {"url": None, "delivery_mode": "DENIED", "expires_at": None}

    ref = str(reference).strip()
    if not ref:
        return {"url": None, "delivery_mode": "DENIED", "expires_at": None}

    # 1. Already a fully-qualified public URL
    if ref.startswith(("http://", "https://")):
        return {"url": ref, "delivery_mode": "DIRECT_PUBLIC", "expires_at": None}

    # 2. Local public static asset (app logos, brand icons, UI assets)
    if ref.startswith("static/"):
        static_url = f"{Config.BASE_URL.rstrip('/')}/{ref.lstrip('/')}"
        return {"url": static_url, "delivery_mode": "DIRECT_STATIC", "expires_at": None}

    fallback_proxy_url = f"{Config.BASE_URL.rstrip('/')}/api/mobile/v1/media?ref={quote(ref, safe='')}"

    # 3. R2 Hosted Asset
    if is_r2_reference(ref):
        if r2_enabled():
            # Strict authorization check before generating signed URL
            if viewer_id and viewer_role and is_authorized_viewer(viewer_id, viewer_role, ref):
                try:
                    ttl = max(300, min(expires_seconds, 900))  # strictly 5 - 15 minutes
                    signed_url = signed_download_url(ref, expires_seconds=ttl)
                    expires_at = int(time.time()) + ttl
                    return {
                        "url": signed_url,
                        "delivery_mode": "DIRECT_SIGNED",
                        "expires_at": expires_at,
                    }
                except PermissionError:
                    # Child surface locked, quiet hours, or screen time gate failed
                    return {"url": None, "delivery_mode": "DENIED", "expires_at": None}
                except Exception:
                    # Transient error generating presigned URL; fall back to authenticated proxy
                    return {"url": fallback_proxy_url, "delivery_mode": "PROXY_FALLBACK", "expires_at": None}
            elif viewer_id and viewer_role:
                # Explicit viewer provided but unauthorized: FAIL CLOSED
                return {"url": None, "delivery_mode": "DENIED", "expires_at": None}

        # Fallback to proxy if R2 is not configured or viewer is not pre-bound
        return {"url": fallback_proxy_url, "delivery_mode": "PROXY_FALLBACK", "expires_at": None}

    # 4. Local uploads directory asset (development / non-R2 test environments)
    return {"url": fallback_proxy_url, "delivery_mode": "PROXY_FALLBACK", "expires_at": None}


def format_asset_url(
    reference: str | None,
    viewer_id: int | None = None,
    viewer_role: str | None = None,
) -> str | None:
    """Convenience helper returning just the URL string for backward compatibility."""
    result = resolve_media_delivery(reference, viewer_id=viewer_id, viewer_role=viewer_role)
    return result.get("url")
