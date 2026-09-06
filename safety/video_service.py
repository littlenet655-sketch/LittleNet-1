"""Scene-aware LittleNet video moderation.

Combines PySceneDetect scene evidence with the existing evenly-distributed frame
budget. This module is the runtime video entry point; visual_service.check_video
is retained temporarily for compatibility with older imports/tests.
"""
from __future__ import annotations

import os
import tempfile

from .common import normalize_signals, timed_call, timeout_seconds
from .scene_sampler import combined_frame_indices
from .visual_service import check_image, _video_sample_count


def _frame_count(path: str):
    import cv2
    cap = cv2.VideoCapture(path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    cap.release()
    return total


def _sample_frames(path: str, requested: int):
    import cv2
    from .policy import decide

    cap = cv2.VideoCapture(path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if total <= 0:
        cap.release()
        return [], []
    indices = combined_frame_indices(path, total, requested)
    outs = []
    inspected = []
    try:
        for idx in indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(idx))
            good, frame = cap.read()
            if not good:
                continue
            fd, tmp = tempfile.mkstemp(suffix=".jpg")
            os.close(fd)
            cv2.imwrite(tmp, frame)
            try:
                signals = check_image(tmp)
                outs.append(signals)
                inspected.append(int(idx))
                if decide(signals).action == "BLOCK":
                    break
            finally:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
    finally:
        cap.release()
    return outs, inspected


def check_video(path: str, max_frames=None):
    """Moderate a video using scene-aware + time-distributed frame evidence."""
    from .remote_client import enabled, moderate_file

    if enabled():
        try:
            return normalize_signals(moderate_file("VIDEO", path), category="VIDEO")
        except Exception:
            return normalize_signals(
                {"total_safety_failure": True, "category": "VIDEO", "errors": ["remote_ai_unavailable"]},
                category="VIDEO",
            )

    try:
        requested = _video_sample_count(path, max_frames)
        outs, indices = timed_call(
            "video_frames",
            lambda: _sample_frames(path, requested),
            timeout_seconds("video_frames", 240),
        )
        if not outs:
            return normalize_signals(
                {"total_safety_failure": True, "category": "VIDEO", "errors": ["no_video_frames"]},
                category="VIDEO",
            )
        keys = ["adult_score", "sexual_score", "weapon_score", "violence_score", "general_score"]
        out = {k: max(float(x.get(k, 0)) for x in outs) for k in keys}
        out["toxicity_score"] = 0
        out["partial_safety_failure"] = any(x.get("partial_safety_failure") for x in outs)
        out["total_safety_failure"] = all(x.get("total_safety_failure") for x in outs)
        out["errors"] = [err for x in outs for err in x.get("errors", [])]
        out["model_signals"] = {
            "sampling_strategy": "pyscenedetect_plus_uniform",
            "sampled_frames": len(outs),
            "requested_frames": requested,
            "frame_indices": indices,
            "frames": [x.get("model_signals", {}) for x in outs],
        }
        out["category"] = (
            "ADULT" if max(out["adult_score"], out["sexual_score"]) >= .4
            else ("WEAPON" if out["weapon_score"] >= .45 else "VIDEO")
        )
        return normalize_signals(out, category="VIDEO")
    except Exception as exc:
        return normalize_signals(
            {
                "total_safety_failure": True,
                "category": "VIDEO",
                "errors": ["video_timeout" if "timeout" in str(exc).lower() else "video_processing"],
            },
            category="VIDEO",
        )
