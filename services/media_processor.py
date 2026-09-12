"""Media processing worker for LittleNet Phase 2 asynchronous uploads.

Validates quarantine media, executes bounded frame sampling and safety checks,
generates posters / faststart video derivatives, and atomically transitions
posts from quarantine to published or review/blocked states.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from config import Config
from database.connection import execute, fetch_all, fetch_one
from safety.moderation_service import evaluate, record, safety_level
from safety.policy import decide
from services import object_storage
from services.media_sanitizer import strip_video_audio_in_place
from services.social import parent_notify


def _notify_approved_followers(post_id: int, child_id: int, kind: str) -> None:
    """Idempotently notify eligible approved followers when content reaches ALLOWED."""
    try:
        user = fetch_one("SELECT full_name, username FROM users WHERE user_id=%s", (child_id,))
        author_name = (user.get("full_name") or user.get("username") or "A friend") if user else "A friend"

        k_lower = str(kind or "post").lower()
        if k_lower == "reel":
            msg = f"{author_name} posted a new Reel"
            notif_type = "NEW_REEL"
            target_url = f"/kids/reels?id={post_id}"
        elif k_lower == "story":
            msg = f"{author_name} added to their Story"
            notif_type = "NEW_STORY"
            target_url = f"/kids/story-viewer?id={post_id}"
        else:
            msg = f"{author_name} shared a new post"
            notif_type = "NEW_POST"
            target_url = f"/kids/home?post_id={post_id}"

        execute(
            """INSERT INTO notifications(user_id, actor_id, notification_type, message, target_url)
               SELECT f.child_id, %s, %s, %s, %s
               FROM followers f
               WHERE f.following_child_id = %s AND f.approved = TRUE AND f.approval_stage = 'ACTIVE'
               AND NOT EXISTS (
                   SELECT 1 FROM notifications n
                   WHERE n.user_id = f.child_id AND n.actor_id = %s
                     AND n.notification_type = %s AND n.target_url = %s
               )""",
            (child_id, notif_type, msg, target_url, child_id, child_id, notif_type, target_url),
        )
    except Exception:
        pass


def _make_video_derivatives(source_path: Path, temp_dir: Path) -> tuple[Path, Path | None]:
    """Generate +faststart video and poster thumbnail using ffmpeg if available.
    Fails closed if audio stripping or processing fails.
    """
    clean_video = temp_dir / f"clean_{source_path.name}"
    poster_image = temp_dir / f"poster_{source_path.stem}.jpg"

    # Always strip audio for child safety — fail closed on exception
    shutil.copy2(source_path, clean_video)
    try:
        strip_video_audio_in_place(str(clean_video))
    except Exception as exc:
        raise RuntimeError(f"video_sanitization_failed: {exc}") from exc

    if not shutil.which("ffmpeg"):
        return clean_video, None

    try:
        # Faststart MP4
        faststart_path = temp_dir / f"fast_{source_path.stem}.mp4"
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(clean_video),
            "-c:v", "libx264", "-preset", "fast", "-crf", "23",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            "-an", str(faststart_path),
        ]
        res = subprocess.run(cmd, capture_output=True, timeout=60)
        final_video = faststart_path if res.returncode == 0 and faststart_path.is_file() else clean_video

        # Poster thumbnail
        poster_cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-ss", "0.2", "-i", str(final_video),
            "-frames:v", "1", "-vf", "scale=480:-2", str(poster_image),
        ]
        res_p = subprocess.run(poster_cmd, capture_output=True, timeout=30)
        final_poster = poster_image if res_p.returncode == 0 and poster_image.is_file() else None
        return final_video, final_poster
    except Exception as exc:
        raise RuntimeError(f"video_transcoding_failed: {exc}") from exc



def _merge_signals(text_signals: dict | None, media_signals: dict | None) -> dict:
    t = text_signals or {}
    m = media_signals or {}
    merged_models = {}
    if isinstance(t.get("model_signals"), dict):
        merged_models.update(t["model_signals"])
    if isinstance(m.get("model_signals"), dict):
        merged_models.update(m["model_signals"])

    return {
        "adult_score": max(float(t.get("adult_score") or 0.0), float(m.get("adult_score") or 0.0)),
        "violence_score": max(float(t.get("violence_score") or 0.0), float(m.get("violence_score") or 0.0)),
        "weapon_score": max(float(t.get("weapon_score") or 0.0), float(m.get("weapon_score") or 0.0)),
        "toxicity_score": max(float(t.get("toxicity_score") or 0.0), float(m.get("toxicity_score") or 0.0)),
        "risk_score": max(float(t.get("risk_score") or 0.0), float(m.get("risk_score") or 0.0)),
        "partial_safety_failure": bool(t.get("partial_safety_failure") or m.get("partial_safety_failure")),
        "total_safety_failure": bool(t.get("total_safety_failure") or m.get("total_safety_failure")),
        "model_signals": merged_models,
        "details": {
            "text": t,
            "media": m,
        },
    }


def process_media_job(post_id: int, child_id: int, object_key: str, kind: str) -> dict[str, Any]:
    """Worker task entry point. Idempotent: safe to run multiple times."""
    post = fetch_one(
        """SELECT post_id, child_id, media_type, caption, content_category,
                  audience_age_group, is_story, is_reel, processing_status, moderation_status
           FROM posts WHERE post_id=%s""",
        (post_id,),
    )
    if not post:
        return {"ok": False, "error": "post_not_found"}

    # Idempotent skip if already terminal
    if post["processing_status"] in ("ALLOWED", "BLOCKED", "REVIEW"):
        return {"ok": True, "status": post["processing_status"], "idempotent": True}

    # Check quarantine object size via head_object if storage enabled
    if object_storage.enabled():
        try:
            head = object_storage.head_object(object_key)
            if head and head.get("ContentLength", 0) > Config.MAX_CONTENT_LENGTH:
                try:
                    object_storage.delete_reference(object_key)
                except Exception:
                    pass
                execute(
                    """UPDATE posts
                       SET processing_status='FAILED', processing_error='upload_size_exceeded',
                           processing_completed_at=NOW()
                       WHERE post_id=%s""",
                    (post_id,),
                )
                return {"ok": False, "error": "upload_size_exceeded"}
        except Exception:
            pass

    # Mark PROCESSING
    execute(
        """UPDATE posts
           SET processing_status='PROCESSING', processing_started_at=COALESCE(processing_started_at, NOW())
           WHERE post_id=%s""",
        (post_id,),
    )

    tags_rows = fetch_all("SELECT tag FROM post_tags WHERE post_id=%s", (post_id,))
    tags_text = " ".join(f"#{r['tag']}" for r in tags_rows)
    combined_text = f"{post.get('caption') or ''} {tags_text}".strip()

    media_type = post.get("media_type") or "VIDEO"
    temp_dir = Path(tempfile.mkdtemp(prefix=f"littlenet_proc_{post_id}_"))

    try:
        source_local = temp_dir / "quarantine_source"
        if object_storage.enabled():
            object_storage.download_file(object_key, source_local)
        else:
            candidate = Path(object_key)
            if not candidate.is_file():
                for mock_candidate in Path("uploads/mock_quarantine").rglob("*"):
                    if mock_candidate.is_file() and object_key in str(mock_candidate):
                        candidate = mock_candidate
                        break
            if candidate.is_file() and candidate.stat().st_size > 0:
                shutil.copy2(candidate, source_local)

        if not source_local.is_file() or source_local.stat().st_size <= 0:
            execute(
                """UPDATE posts
                   SET processing_status='FAILED', processing_error='quarantine_media_missing_or_empty',
                       processing_completed_at=NOW()
                   WHERE post_id=%s""",
                (post_id,),
            )
            return {"ok": False, "error": "quarantine_media_missing_or_empty"}

        if source_local.is_file() and source_local.stat().st_size > Config.MAX_CONTENT_LENGTH:
            execute(
                """UPDATE posts
                   SET processing_status='FAILED', processing_error='upload_size_exceeded',
                       processing_completed_at=NOW()
                   WHERE post_id=%s""",
                (post_id,),
            )
            return {"ok": False, "error": "upload_size_exceeded"}

        final_media_local = source_local
        final_poster_local = None

        if media_type == "VIDEO":
            from safety.visual_service import video_duration_seconds

            duration = video_duration_seconds(str(source_local))
            limit = (
                Config.REEL_MAX_SECONDS
                if kind.lower() == "reel"
                else Config.STORY_MAX_SECONDS
                if kind.lower() == "story"
                else Config.VIDEO_MAX_SECONDS
            )
            if duration > limit:
                execute(
                    """UPDATE posts
                       SET processing_status='FAILED', processing_error='video_duration_exceeded',
                           processing_completed_at=NOW()
                       WHERE post_id=%s""",
                    (post_id,),
                )
                return {"ok": False, "error": "video_duration_exceeded"}

            final_media_local, final_poster_local = _make_video_derivatives(source_local, temp_dir)
        elif media_type == "IMAGE":
            try:
                from PIL import Image, ImageOps
                with Image.open(source_local) as img:
                    img = ImageOps.exif_transpose(img)
                    clean_img_path = temp_dir / "clean_image.jpg"
                    # Strip EXIF/GPS by saving a fresh clean JPEG RGB image
                    img.convert("RGB").save(clean_img_path, format="JPEG", quality=92, optimize=True)
                    if not clean_img_path.is_file() or clean_img_path.stat().st_size == 0:
                        raise RuntimeError("clean_image_empty")
                    final_media_local = clean_img_path
            except Exception as exc:
                raise RuntimeError(f"image_sanitization_failed: {exc}") from exc


        # AI Moderation
        text_signals, _ = evaluate(child_id, "TEXT", combined_text) if combined_text else ({}, None)
        media_signals, _ = evaluate(child_id, media_type, str(final_media_local))
        merged = _merge_signals(text_signals, media_signals)
        decision = decide(merged, safety_level(child_id), Config.ADULT_HARD_BLOCK_THRESHOLD)
        event_id = record(child_id, media_type, post_id, merged, decision)

        if decision.action == "BLOCK":
            execute(
                """UPDATE posts
                   SET is_safe=FALSE, moderation_status='BLOCKED', processing_status='BLOCKED',
                       media_path=NULL,
                       safety_score=%s, adult_score=%s, violence_score=%s, weapon_score=%s,
                       toxicity_score=%s, moderation_reason=%s, processing_completed_at=NOW()
                   WHERE post_id=%s""",
                (
                    decision.risk,
                    merged["adult_score"] * 100,
                    merged["violence_score"] * 100,
                    merged["weapon_score"] * 100,
                    merged["toxicity_score"] * 100,
                    decision.reason,
                    post_id,
                ),
            )
            parent_notify(child_id, "CONTENT_BLOCKED", decision.reason, "/parent/safety/")
            block_and_cleanup_quarantine(post_id, object_key)
            return {"ok": True, "status": "BLOCKED", "reason": decision.reason}

        elif decision.action == "REVIEW":
            execute(
                """UPDATE posts
                   SET is_safe=FALSE, moderation_status='REVIEW', processing_status='REVIEW',
                       safety_score=%s, adult_score=%s, violence_score=%s, weapon_score=%s,
                       toxicity_score=%s, moderation_reason=%s, processing_completed_at=NOW()
                   WHERE post_id=%s""",
                (
                    decision.risk,
                    merged["adult_score"] * 100,
                    merged["violence_score"] * 100,
                    merged["weapon_score"] * 100,
                    merged["toxicity_score"] * 100,
                    decision.reason,
                    post_id,
                ),
            )
            parent_notify(
                child_id,
                "REVIEW_REQUIRED",
                "Content is waiting for your review",
                f"/parent/safety/?event={event_id}",
            )
            return {"ok": True, "status": "REVIEW", "event_id": event_id}

        else:  # ALLOW
            ext = "mp4" if media_type == "VIDEO" else "jpg"
            media_mime = "video/mp4" if ext == "mp4" else "image/jpeg"
            namespace = "stories" if kind.lower() == "story" else "reels" if kind.lower() == "reel" else "posts"
            published_media_ref = f"uploads/r2/{namespace}/{child_id}/{post_id}_media.{ext}"
            published_poster_ref = None

            if object_storage.enabled():
                object_storage.upload_file(str(final_media_local), f"{namespace}/{child_id}/{post_id}_media.{ext}", content_type=media_mime)
                if final_poster_local and final_poster_local.is_file():
                    published_poster_ref = f"uploads/r2/{namespace}/{child_id}/{post_id}_poster.jpg"
                    object_storage.upload_file(
                        str(final_poster_local), f"{namespace}/{child_id}/{post_id}_poster.jpg", content_type="image/jpeg"
                    )
            else:
                local_pub_dir = Path("uploads") / namespace / str(child_id)
                local_pub_dir.mkdir(parents=True, exist_ok=True)
                perm_media = local_pub_dir / f"{post_id}_media.{ext}"
                shutil.copy2(final_media_local, perm_media)
                published_media_ref = str(perm_media).replace("\\", "/")

                published_poster_ref = None
                if final_poster_local and final_poster_local.is_file():
                    perm_poster = local_pub_dir / f"{post_id}_poster.jpg"
                    shutil.copy2(final_poster_local, perm_poster)
                    published_poster_ref = str(perm_poster).replace("\\", "/")

            execute(
                """UPDATE posts
                   SET media_path=%s, poster_path=%s, is_safe=TRUE,
                       moderation_status='ALLOWED', processing_status='ALLOWED',
                       safety_score=%s, adult_score=%s, violence_score=%s, weapon_score=%s,
                       toxicity_score=%s, moderation_reason=%s, processing_completed_at=NOW()
                   WHERE post_id=%s""",
                (
                    published_media_ref,
                    published_poster_ref,
                    decision.risk,
                    merged["adult_score"] * 100,
                    merged["violence_score"] * 100,
                    merged["weapon_score"] * 100,
                    merged["toxicity_score"] * 100,
                    decision.reason,
                    post_id,
                ),
            )
            _notify_approved_followers(post_id, child_id, kind)
            block_and_cleanup_quarantine(post_id, object_key)
            return {
                "ok": True,
                "status": "ALLOWED",
                "media_path": published_media_ref,
                "poster_path": published_poster_ref,
            }

    except Exception as exc:
        execute(
            """UPDATE posts
               SET processing_status='FAILED', processing_error=%s, processing_completed_at=NOW()
               WHERE post_id=%s""",
            (str(exc), post_id),
        )
        return {"ok": False, "error": str(exc)}

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def sanitize_and_promote_media(
    post_id: int, child_id: int, object_key: str, kind: str, media_type: str
) -> tuple[str, str | None]:
    """Sanitize quarantine media and promote bytes to the published namespace.

    Fails closed: raises RuntimeError on any sanitization or storage failure so
    unmoderated or unsanitized bytes are never published.
    """
    temp_dir = Path(tempfile.mkdtemp(prefix=f"littlenet_promote_{post_id}_"))
    try:
        source_local = temp_dir / "quarantine_source"
        if object_storage.enabled():
            object_storage.download_file(object_key, source_local)
        else:
            candidate = Path(object_key)
            if not candidate.is_file():
                for mock_candidate in Path("uploads/mock_quarantine").rglob("*"):
                    if mock_candidate.is_file() and object_key in str(mock_candidate):
                        candidate = mock_candidate
                        break
            if candidate.is_file():
                shutil.copy2(candidate, source_local)

        if not source_local.is_file() or source_local.stat().st_size <= 0:
            raise RuntimeError("quarantine_media_missing_or_empty")

        final_media_local = source_local
        final_poster_local = None

        ext = "mp4" if media_type.upper() == "VIDEO" else "jpg"
        media_mime = "video/mp4" if ext == "mp4" else "image/jpeg"

        if media_type.upper() == "VIDEO":
            final_media_local, final_poster_local = _make_video_derivatives(source_local, temp_dir)
        elif media_type.upper() == "IMAGE":
            try:
                from PIL import Image, ImageOps

                with Image.open(source_local) as img:
                    img = ImageOps.exif_transpose(img)
                    clean_img_path = temp_dir / "clean_image.jpg"
                    img.convert("RGB").save(clean_img_path, format="JPEG", quality=92, optimize=True)
                    if not clean_img_path.is_file() or clean_img_path.stat().st_size == 0:
                        raise RuntimeError("clean_image_empty")
                    final_media_local = clean_img_path
            except Exception as exc:
                raise RuntimeError(f"image_sanitization_failed: {exc}") from exc

        namespace = "stories" if kind.lower() == "story" else "reels" if kind.lower() == "reel" else "posts"

        if object_storage.enabled():
            published_media_ref = f"uploads/r2/{namespace}/{child_id}/{post_id}_media.{ext}"
            published_poster_ref = None
            object_storage.upload_file(str(final_media_local), f"{namespace}/{child_id}/{post_id}_media.{ext}", content_type=media_mime)
            if final_poster_local and final_poster_local.is_file():
                published_poster_ref = f"uploads/r2/{namespace}/{child_id}/{post_id}_poster.jpg"
                object_storage.upload_file(
                    str(final_poster_local), f"{namespace}/{child_id}/{post_id}_poster.jpg", content_type="image/jpeg"
                )
            # Caller deletes quarantine object_key AFTER database state commits!
        else:
            # Local persistent storage: copy into permanent local directory
            local_pub_dir = Path("uploads") / namespace / str(child_id)
            local_pub_dir.mkdir(parents=True, exist_ok=True)
            perm_media = local_pub_dir / f"{post_id}_media.{ext}"
            shutil.copy2(final_media_local, perm_media)
            published_media_ref = str(perm_media).replace("\\", "/")

            published_poster_ref = None
            if final_poster_local and final_poster_local.is_file():
                perm_poster = local_pub_dir / f"{post_id}_poster.jpg"
                shutil.copy2(final_poster_local, perm_poster)
                published_poster_ref = str(perm_poster).replace("\\", "/")

        return published_media_ref, published_poster_ref
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def block_and_cleanup_quarantine(post_id: int, object_key: str | None) -> None:
    """Delete and invalidate quarantine media on moderation BLOCK (called after DB commit)."""
    if not object_key:
        return
    cleaned = True
    if object_storage.enabled():
        try:
            object_storage.delete_reference(object_key)
        except Exception:
            cleaned = False
    try:
        for p in Path("uploads/mock_quarantine").rglob("*"):
            if p.is_file() and object_key in str(p):
                p.unlink(missing_ok=True)
    except Exception:
        pass

    if not cleaned:
        try:
            from services.media_outbox import enqueue_delete
            enqueue_delete(object_key, "posts", post_id)
        except Exception:
            pass

    return cleaned


def redrive_media_job(post_id: int, force: bool = False) -> dict[str, Any]:
    """Redrive an individual stalled or failed media processing job with bounded attempts and backoff."""
    from datetime import datetime, timedelta, timezone

    post = fetch_one(
        """SELECT post_id, child_id, source_media_path, is_reel, is_story,
                  processing_status, moderation_status, processing_attempts,
                  max_processing_attempts, last_attempt_at
           FROM posts WHERE post_id=%s""",
        (post_id,),
    )
    if not post:
        return {"ok": False, "error": "post_not_found"}
    if post.get("processing_status") in ("ALLOWED", "BLOCKED"):
        return {"ok": True, "status": post["processing_status"], "idempotent": True}

    attempts = int(post.get("processing_attempts") or 0)
    max_attempts = int(post.get("max_processing_attempts") or 3)

    if attempts >= max_attempts and not force:
        execute(
            """UPDATE posts
               SET processing_status='FAILED', processing_error='max_attempts_exceeded',
                   processing_completed_at=NOW()
               WHERE post_id=%s""",
            (post_id,),
        )
        return {
            "ok": False,
            "error": "max_attempts_exceeded",
            "status": "FAILED",
            "attempts": attempts,
            "max_attempts": max_attempts,
        }

    last_att = post.get("last_attempt_at")
    if last_att and not force:
        now = datetime.now(timezone.utc)
        if hasattr(last_att, "tzinfo") and last_att.tzinfo is None:
            last_att = last_att.replace(tzinfo=timezone.utc)
        backoff_sec = min(300, (2 ** max(0, attempts - 1)) * 5)
        elapsed = (now - last_att).total_seconds()
        if elapsed < backoff_sec:
            rem = int(backoff_sec - elapsed)
            return {
                "ok": False,
                "error": "backoff_in_progress",
                "retry_after_seconds": rem,
                "attempts": attempts,
            }

    kind = "reel" if post.get("is_reel") else ("story" if post.get("is_story") else "post")
    object_key = post.get("source_media_path")
    if not object_key:
        return {"ok": False, "error": "missing_source_media_path"}

    from services.job_queue import enqueue_media_job

    execute(
        """UPDATE posts
           SET processing_status='PROCESSING', processing_started_at=NOW(), last_attempt_at=NOW(),
               processing_attempts=processing_attempts+1, processing_error=NULL
           WHERE post_id=%s""",
        (post_id,),
    )
    try:
        job_id = enqueue_media_job(post_id, int(post["child_id"]), object_key, kind)
        execute("UPDATE posts SET job_id=%s WHERE post_id=%s", (job_id, post_id))
        return {
            "ok": True,
            "post_id": post_id,
            "job_id": job_id,
            "status": "PROCESSING",
            "attempts": attempts + 1,
        }
    except Exception as exc:
        execute(
            """UPDATE posts SET processing_status='UPLOADED', processing_error=%s WHERE post_id=%s""",
            (f"redrive_dispatch_failed: {exc}", post_id),
        )
        return {"ok": False, "error": "job_dispatch_failed", "detail": str(exc)}


def reap_stale_media_jobs(stale_seconds: int = 300) -> dict[str, Any]:
    """Find posts stuck in UPLOADED or PROCESSING longer than stale_seconds, respect max attempts, and redrive them."""
    from datetime import datetime, timedelta, timezone

    stale_seconds = max(30, min(int(stale_seconds), 86400))
    threshold = datetime.now(timezone.utc) - timedelta(seconds=stale_seconds)

    stale_posts = fetch_all(
        """SELECT post_id, child_id, source_media_path, is_reel, is_story,
                  processing_status, processing_started_at, created_at,
                  processing_attempts, max_processing_attempts
           FROM posts
           WHERE processing_status IN ('UPLOADED', 'PROCESSING')
             AND (processing_started_at < %s OR (processing_started_at IS NULL AND created_at < %s))
           ORDER BY post_id ASC LIMIT 50""",
        (threshold, threshold),
    )

    redriven = []
    failed = []
    from services.job_queue import enqueue_media_job

    for p in (stale_posts or []):
        post_id = int(p["post_id"])
        child_id = int(p["child_id"])
        object_key = p["source_media_path"]
        attempts = int(p.get("processing_attempts") or 0)
        max_attempts = int(p.get("max_processing_attempts") or 3)

        if attempts >= max_attempts:
            # Terminal FAILED state: prevent infinite reaper loops
            execute(
                """UPDATE posts
                   SET processing_status='FAILED', processing_error='max_attempts_exceeded_stale_reap',
                       processing_completed_at=NOW()
                   WHERE post_id=%s""",
                (post_id,),
            )
            failed.append({"post_id": post_id, "error": "max_attempts_exceeded"})
            continue

        if not object_key:
            continue

        kind = "reel" if p.get("is_reel") else ("story" if p.get("is_story") else "post")
        try:
            execute(
                """UPDATE posts
                   SET processing_status='PROCESSING', processing_started_at=NOW(), last_attempt_at=NOW(),
                       processing_attempts=processing_attempts+1, processing_error=NULL
                   WHERE post_id=%s""",
                (post_id,),
            )
            job_id = enqueue_media_job(post_id, child_id, object_key, kind)
            execute("UPDATE posts SET job_id=%s WHERE post_id=%s", (job_id, post_id))
            redriven.append({"post_id": post_id, "job_id": job_id, "attempts": attempts + 1})
        except Exception as exc:
            execute(
                """UPDATE posts SET processing_status='UPLOADED', processing_error=%s WHERE post_id=%s""",
                (f"reap_dispatch_failed: {exc}", post_id),
            )
            failed.append({"post_id": post_id, "error": str(exc)})

    return {"ok": True, "count": len(redriven), "redriven": redriven, "failed": failed}


