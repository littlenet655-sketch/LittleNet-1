"""Cost-guarded direct client for LittleNet's CPU image moderation function.

Production image uploads use a Modal CPU function by default. This keeps the T4
reserved for workloads that actually need it (for example video/face paths).
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any


def enabled() -> bool:
    raw = os.getenv("LITTLENET_USE_MODAL_IMAGE_CPU", "0").strip().lower()
    return raw in {"1", "true", "yes", "on"}


def allow_gpu_fallback() -> bool:
    raw = os.getenv("LITTLENET_ALLOW_IMAGE_GPU_FALLBACK", "0").strip().lower()
    return raw in {"1", "true", "yes", "on"}


def moderate_image_upload(
    path: str,
    text: str = "",
    *,
    run_text: bool = True,
    run_media: bool = True,
) -> dict[str, Any]:
    if not enabled():
        raise RuntimeError("modal_image_cpu_disabled")

    import modal

    app_name = os.getenv("LITTLENET_AI_MODAL_APP", "littlenet-ai").strip() or "littlenet-ai"
    function_name = os.getenv(
        "LITTLENET_AI_IMAGE_CPU_FUNCTION",
        "moderate_image_upload_cpu",
    ).strip() or "moderate_image_upload_cpu"

    fn = modal.Function.from_name(app_name, function_name)
    payload = Path(path).read_bytes()
    if not payload:
        raise RuntimeError("image_payload_empty")

    result = fn.remote(
        payload,
        Path(path).name,
        (text or "")[:4000],
        bool(run_text),
        bool(run_media),
    )
    if not isinstance(result, dict) or result.get("ok") is not True:
        raise RuntimeError("modal_image_cpu_invalid_result")

    text_signals = result.get("text_signals")
    media_signals = result.get("media_signals")
    if run_text and not isinstance(text_signals, dict):
        raise RuntimeError("modal_image_cpu_text_missing")
    if run_media and (not isinstance(media_signals, dict) or not media_signals):
        raise RuntimeError("modal_image_cpu_media_missing")

    return {
        "text_signals": text_signals if isinstance(text_signals, dict) else {},
        "media_signals": media_signals if isinstance(media_signals, dict) else {},
        "compute_tier": "modal_cpu",
    }
