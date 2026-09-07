"""Cloudflare R2 storage adapter for LittleNet media.

The application keeps moderation files on local ephemeral disk only long enough
for safety analysis. Once content is accepted, callers persist it here before the
corresponding PostgreSQL row is published.
"""
from __future__ import annotations

import mimetypes
import os
from pathlib import Path
from typing import Optional

R2_REFERENCE_PREFIX = "uploads/r2/"


def _enabled() -> bool:
    return all(os.getenv(name) for name in ("R2_ACCOUNT_ID","R2_ACCESS_KEY_ID","R2_SECRET_ACCESS_KEY","R2_BUCKET"))


def enabled() -> bool:return _enabled()


def healthcheck() -> dict:
    if not _enabled():return {"ok": False, "configured": False, "bucket": os.getenv("R2_BUCKET") or None}
    try:
        _client().head_bucket(Bucket=os.environ["R2_BUCKET"])
        return {"ok": True, "configured": True, "bucket": os.environ["R2_BUCKET"]}
    except Exception as exc:
        return {"ok": False,"configured": True,"bucket": os.getenv("R2_BUCKET") or None,"error": f"{type(exc).__name__}: {exc}"}


def is_reference(reference: str | None) -> bool:
    return bool(reference and str(reference).startswith(R2_REFERENCE_PREFIX))


def _client():
    if not _enabled():raise RuntimeError("Cloudflare R2 is not configured")
    import boto3
    return boto3.client("s3",endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],region_name="auto")


def upload_file(local_path: str, key: str, content_type: Optional[str] = None) -> str:
    """Upload moderated content to private R2; video audio is stripped first."""
    path = Path(local_path)
    if not path.is_file():raise FileNotFoundError(local_path)
    ctype = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if ctype.lower().startswith('video/'):
        from services.media_sanitizer import strip_video_audio_in_place
        strip_video_audio_in_place(str(path))
    _client().upload_file(str(path),os.environ["R2_BUCKET"],key,ExtraArgs={"ContentType": ctype,"CacheControl": "private, no-store, max-age=0"})
    return f"uploads/r2/{key}"


def delete_reference(reference: str) -> None:
    if not is_reference(reference) or not _enabled():return
    _client().delete_object(Bucket=os.environ["R2_BUCKET"],Key=str(reference)[len(R2_REFERENCE_PREFIX):])


def _request_media_gate() -> None:
    """Prevent a signed URL from bypassing child account/time/onboarding controls."""
    try:
        from flask import has_request_context,session
        if not has_request_context() or session.get('role')!='CHILD':return
        uid=int(session.get('user_id') or 0)
        if not uid:raise PermissionError('child_session_required')
        from services.social import child_surface_open
        if not child_surface_open(uid):raise PermissionError('child_media_locked')
    except PermissionError:
        raise
    except Exception as exc:
        raise PermissionError('child_media_gate_unavailable') from exc


def signed_download_url(reference: str, expires_seconds: int | None = None) -> str:
    if not is_reference(reference):raise ValueError("not an R2 reference")
    if not _enabled():raise RuntimeError("Cloudflare R2 is not configured")
    _request_media_gate()
    expiry = expires_seconds or int(os.getenv("R2_SIGNED_URL_TTL", "180"))
    return _client().generate_presigned_url("get_object",Params={"Bucket": os.environ["R2_BUCKET"],"Key": str(reference)[len(R2_REFERENCE_PREFIX):]},ExpiresIn=max(60, min(expiry, 600)))
