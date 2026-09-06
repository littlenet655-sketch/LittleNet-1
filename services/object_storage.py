"""Cloudflare R2 storage adapter for LittleNet media.

The application keeps moderation files on local ephemeral disk only long enough
for safety analysis. Once content is accepted, callers can persist it here and
store the returned ``uploads/r2/<key>`` reference in PostgreSQL.

R2 is S3-compatible. The bucket can remain private: ``signed_download_url``
creates a short-lived URL after LittleNet has performed its existing access
checks in /uploads/<path>.
"""
from __future__ import annotations

import mimetypes
import os
from pathlib import Path
from typing import Optional


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
            "CacheControl": "private, max-age=300",
        },
    )
    return f"uploads/r2/{key}"


def delete_reference(reference: str) -> None:
    """Delete an R2 object referenced as uploads/r2/<key>. No-op for local files."""
    prefix = "uploads/r2/"
    if not reference or not reference.startswith(prefix) or not _enabled():
        return
    _client().delete_object(Bucket=os.environ["R2_BUCKET"], Key=reference[len(prefix):])


def signed_download_url(reference: str, expires_seconds: int | None = None) -> str:
    """Return a short-lived private R2 GET URL for an authorized LittleNet request."""
    prefix = "uploads/r2/"
    if not reference.startswith(prefix):
        raise ValueError("not an R2 reference")
    expiry = expires_seconds or int(os.getenv("R2_SIGNED_URL_TTL", "300"))
    return _client().generate_presigned_url(
        "get_object",
        Params={"Bucket": os.environ["R2_BUCKET"], "Key": reference[len(prefix):]},
        ExpiresIn=max(60, min(expiry, 3600)),
    )
