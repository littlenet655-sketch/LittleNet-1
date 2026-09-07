"""Cloudflare R2 storage adapter for LittleNet media.

The application keeps moderation files on local ephemeral disk only long enough
for safety analysis. Once content is accepted, callers can persist it here and
store the returned ``uploads/r2/<key>`` reference in PostgreSQL.

R2 is S3-compatible. The bucket remains private: ``signed_download_url`` creates
a short-lived URL only after LittleNet has performed its existing access checks
in ``/uploads/<path>``.
"""
from __future__ import annotations

import mimetypes
import os
from pathlib import Path
from typing import Optional


R2_REFERENCE_PREFIX = "uploads/r2/"


def _enabled() -> bool:
    return all(
        os.getenv(name)
        for name in (
            "R2_ACCOUNT_ID",
            "R2_ACCESS_KEY_ID",
            "R2_SECRET_ACCESS_KEY",
            "R2_BUCKET",
        )
    )


def enabled() -> bool:
    return _enabled()


def healthcheck() -> dict:
    """Read-only production readiness check for the configured private bucket.

    A release must not be marked ready merely because four R2 environment
    variables exist. ``head_bucket`` proves that the credentials can actually
    reach the configured bucket without writing or deleting any child media.
    """
    if not _enabled():
        return {"ok": False, "configured": False, "bucket": os.getenv("R2_BUCKET") or None}
    try:
        _client().head_bucket(Bucket=os.environ["R2_BUCKET"])
        return {"ok": True, "configured": True, "bucket": os.environ["R2_BUCKET"]}
    except Exception as exc:
        return {
            "ok": False,
            "configured": True,
            "bucket": os.getenv("R2_BUCKET") or None,
            "error": f"{type(exc).__name__}: {exc}",
        }


def is_reference(reference: str | None) -> bool:
    return bool(reference and str(reference).startswith(R2_REFERENCE_PREFIX))


def _client():
    if not _enabled():
        raise RuntimeError("Cloudflare R2 is not configured")
    import boto3
    return boto3.client(
        "s3",
        endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        region_name="auto",
    )


def upload_file(local_path: str, key: str, content_type: Optional[str] = None) -> str:
    """Upload one moderated file and return its private R2 DB reference.

    LittleNet intentionally has no speech/audio moderation. Any video is therefore
    converted to a silent video immediately before persistence. If ffmpeg/ffprobe
    cannot prove the audio track is gone, the exception propagates and the caller's
    existing R2 transaction marks the child media BLOCKED instead of publishing it.
    """
    path = Path(local_path)
    if not path.is_file():
        raise FileNotFoundError(local_path)
    ctype = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if ctype.lower().startswith('video/'):
        from services.media_sanitizer import strip_video_audio_in_place
        strip_video_audio_in_place(str(path))
    _client().upload_file(
        str(path),
        os.environ["R2_BUCKET"],
        key,
        ExtraArgs={
            "ContentType": ctype,
            # Child media must never become reusable public browser/CDN cache
            # content. Access is re-authorized by LittleNet on every /uploads/
            # request and the resulting R2 URL is short-lived.
            "CacheControl": "private, no-store, max-age=0",
        },
    )
    # Keep the literal legacy contract because other source/readiness checks
    # intentionally assert this DB reference format.
    return f"uploads/r2/{key}"


def delete_reference(reference: str) -> None:
    """Delete an R2 object referenced as uploads/r2/<key>. No-op for local files."""
    if not is_reference(reference) or not _enabled():
        return
    _client().delete_object(
        Bucket=os.environ["R2_BUCKET"],
        Key=str(reference)[len(R2_REFERENCE_PREFIX):],
    )


def signed_download_url(reference: str, expires_seconds: int | None = None) -> str:
    """Return a short-lived private R2 GET URL for an authorized LittleNet request."""
    if not is_reference(reference):
        raise ValueError("not an R2 reference")
    if not _enabled():
        raise RuntimeError("Cloudflare R2 is not configured")
    expiry = expires_seconds or int(os.getenv("R2_SIGNED_URL_TTL", "180"))
    return _client().generate_presigned_url(
        "get_object",
        Params={
            "Bucket": os.environ["R2_BUCKET"],
            "Key": str(reference)[len(R2_REFERENCE_PREFIX):],
        },
        ExpiresIn=max(60, min(expiry, 600)),
    )
