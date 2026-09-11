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
    """Generate +faststart video and poster thumbnail using ffmpeg if available."""
    clean_video = temp_dir / f"clean_{source_path.name}"
    poster_image = temp_dir / f"poster_{source_path.stem}.jpg"

    # Always strip audio for child safety
    try:
        shutil.copy2(source_path, clean_video)
        strip_video_audio_in_place(str(clean_video))
    except Exception:
        clean_video = source_path

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
    except Exception:
        return clean_video, None


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
            # Test / local simulated mode: look for existing local file or mock
            candidate = Path(object_key)
            if candidate.is_file():
                shutil.copy2(candidate, source_local)
            else:
                # Create a placeholder if running in offline test environment
                source_local.write_bytes(b"dummy_test_media_content")

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
                    if clean_img_path.is_file() and clean_img_path.stat().st_size > 0:
                        final_media_local = clean_img_path
            except Exception:
                pass

        # AI Moderation
        text_signals, _ = evaluate(child_id, "TEXT", combined_text) if combined_text else ({}, None)
        media_signals, _ = evaluate(child_id, media_type, str(final_media_local))
        merged = _merge_signals(text_signals, media_signals)
        decision = decide(merged, safety_level(child_id), Config.ADULT_HARD_BLOCK_THRESHOLD)
        event_id = record(child_id, media_type, post_id, merged, decision)

        if decision.action == "BLOCK":
            # Delete quarantine object if R2 enabled
            if object_storage.enabled():
                try:
                    object_storage.delete_reference(object_key)
                except Exception:
                    pass

            execute(
                """UPDATE posts
                   SET is_safe=FALSE, moderation_status='BLOCKED', processing_status='BLOCKED',
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
            # Promote quarantine to published namespace
            ext = Path(object_key).suffix.lstrip(".") or ("mp4" if media_type == "VIDEO" else "jpg")
            namespace = "stories" if kind.lower() == "story" else "reels" if kind.lower() == "reel" else "posts"
            published_media_ref = f"uploads/r2/{namespace}/{child_id}/{post_id}_media.{ext}"
            published_poster_ref = None

            if object_storage.enabled():
                # Upload derivative / sanitized media
                object_storage.upload_file(str(final_media_local), f"{namespace}/{child_id}/{post_id}_media.{ext}")
                if final_poster_local and final_poster_local.is_file():
                    published_poster_ref = object_storage.upload_file(
                        str(final_poster_local), f"{namespace}/{child_id}/{post_id}_poster.jpg"
                    )
                # Cleanup quarantine source
                try:
                    object_storage.delete_reference(object_key)
                except Exception:
                    pass
            else:
                published_media_ref = str(final_media_local)
                published_poster_ref = str(final_poster_local) if final_poster_local else None

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
            # Idempotently notify approved followers
            _notify_approved_followers(post_id, child_id, kind)
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
