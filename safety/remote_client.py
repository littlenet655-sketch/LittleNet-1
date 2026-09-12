"""Client for the optional split LittleNet AI inference service.

The web app can run with only the lightweight dependencies and delegate heavy
inference (YOLO/NSFW/DeepFace/semantic ranking) to the protected AI service.
Every network request has a centrally bounded timeout and fails closed in its
caller when the AI service is unavailable.
"""
import json
import math
import os
import time
from pathlib import Path

import requests


def enabled() -> bool:
    return bool(os.getenv("AI_SERVICE_URL", "").strip()) and os.getenv("LITTLENET_AI_SERVER") != "1"


def _base() -> str:
    return os.environ["AI_SERVICE_URL"].rstrip("/")


def _headers():
    secret = os.getenv("AI_SHARED_SECRET", "").strip()
    return {"X-LittleNet-AI-Key": secret} if secret else {}


def _timeout() -> int:
    """Return a finite AI timeout; never allow an unbounded remote call."""
    try:
        configured = int(os.getenv("AI_REQUEST_TIMEOUT", "120"))
    except (TypeError, ValueError):
        configured = 120
    return max(10, min(configured, 300))


def _health_timeout() -> int:
    """Deep AI probes may tolerate a Modal cold start but remain bounded."""
    try:
        configured = int(os.getenv("AI_HEALTH_TIMEOUT", "30"))
    except (TypeError, ValueError):
        configured = 30
    return max(10, min(configured, 90))


def _deep_health_enabled() -> bool:
    """Return whether a readiness call is allowed to wake the GPU-backed AI app.

    Infrastructure probes hit `/readyz` frequently. Waking a scaled-to-zero T4
    for each probe is both unnecessary and expensive, so the default readiness
    check validates configuration only. Explicit release diagnostics can opt in
    with `AI_DEEP_HEALTH_PROBE=1` or by calling `health(deep=True)`.
    """
    return os.getenv("AI_DEEP_HEALTH_PROBE", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _json_object(response, name: str) -> dict:
    data = response.json()
    if not isinstance(data, dict):
        raise ValueError(f"{name}_invalid_json")
    return data


def _moderation_signals(response) -> dict:
    data = _json_object(response, "moderation")
    if data.get("ok") is False:
        raise ValueError(str(data.get("error") or "moderation_failed"))
    signals = data.get("signals")
    if not isinstance(signals, dict) or not signals:
        raise ValueError("moderation_signals_missing")
    return signals


def moderate_text(text: str) -> dict:
    r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
        _base() + "/ai/moderate",
        data={"content_type": "TEXT", "text": text or ""},
        headers=_headers(), timeout=_timeout(),
    )
    r.raise_for_status()
    return _moderation_signals(r)


def moderate_file(content_type: str, path: str) -> dict:
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/moderate",
            data={"content_type": content_type.upper()},
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    return _moderation_signals(r)


def face_embedding(path: str) -> list[float]:
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/face/embedding",
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    data = _json_object(r, "face_embedding")
    if data.get("ok") is not True:
        raise ValueError(data.get("reason", "face_error"))
    raw = data.get("embedding")
    if not isinstance(raw, list) or not raw:
        raise ValueError("face_embedding_missing")
    emb=[]
    for value in raw:
        if isinstance(value,bool):raise ValueError("face_embedding_invalid")
        value=float(value)
        if not math.isfinite(value):raise ValueError("face_embedding_invalid")
        emb.append(value)
    return emb


def face_verify(reference, path: str) -> dict:
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/face/verify",
            data={"reference": json.dumps(reference)},
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    data = _json_object(r, "face_verify")
    if data.get("ok") is True:
        if not isinstance(data.get("matched"),bool):raise ValueError("face_verify_matched_invalid")
        distance=data.get("distance")
        if isinstance(distance,bool):raise ValueError("face_verify_distance_invalid")
        distance=float(distance)
        if not math.isfinite(distance):raise ValueError("face_verify_distance_invalid")
        data["distance"]=distance
    elif data.get("ok") is not False:
        raise ValueError("face_verify_ok_invalid")
    return data


def face_adult_verify(path: str) -> dict:
    """Run guardian liveness + adult-age analysis on the heavy AI service."""
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/face/adult",
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    data = _json_object(r, "adult_face")
    if data.get("ok") is not True:
        return {
            "is_adult": False,
            "estimated_age": None,
            "method": "REMOTE_AI",
            "reason": data.get("reason", "adult_face_verification_failed"),
        }
    result=data.get("result")
    if not isinstance(result,dict):
        return {
            "is_adult": False,
            "estimated_age": None,
            "method": "REMOTE_AI",
            "reason": "adult_face_verification_empty",
        }
    if result.get("is_adult") is True:
        try:age=float(result.get("estimated_age"))
        except (TypeError,ValueError):age=float("nan")
        if not math.isfinite(age) or age<18.0:
            return {
                "is_adult": False,
                "estimated_age": None,
                "method": "REMOTE_AI",
                "reason": "adult_face_verification_invalid",
            }
    elif result.get("is_adult") is not False:
        return {
            "is_adult": False,
            "estimated_age": None,
            "method": "REMOTE_AI",
            "reason": "adult_face_verification_invalid",
        }
    return result


def health(*, deep: bool | None = None) -> dict:
    """Return cheap readiness by default and deep remote health on explicit opt-in.

    Modal's AI endpoint is GPU-backed. Frequent infrastructure `/readyz` probes
    must not cold-start or keep a T4 alive, so the default call reports that the
    remote service is configured without making a network request. Release gates,
    diagnostics, or one-off operator checks can call `health(deep=True)` or set
    `AI_DEEP_HEALTH_PROBE=1` to perform the real protected `/healthz` request.
    """
    if deep is None:
        deep = _deep_health_enabled()
    if not deep:
        return {
            "ok": bool(enabled()),
            "status": "configured" if enabled() else "disabled",
            "probe": "skipped",
            "reason": "gpu_probe_disabled_for_runtime_readiness",
        }

    attempts = 3
    try:
        attempts = max(1, min(int(os.getenv("AI_HEALTH_ATTEMPTS", "3")), 5))
    except (TypeError, ValueError):
        attempts = 3
    timeout = _health_timeout()
    last_error = "ai_health_unavailable"
    for attempt in range(1, attempts + 1):
        try:
            r = requests.get(  # nosec B113 - timeout is explicitly bounded above
                _base() + "/healthz", headers=_headers(), timeout=timeout
            )
            r.raise_for_status()
            data = _json_object(r, "health")
            if data.get("ok") is True:
                data.setdefault("probe", "deep")
                return data
            last_error = str(data.get("error") or data.get("status") or "ai_not_ready")
        except (requests.RequestException, ValueError) as exc:
            last_error = f"{type(exc).__name__}: {exc}"
        if attempt < attempts:
            time.sleep(min(2 * attempt, 4))
    return {
        "ok": False,
        "error": "ai_health_unavailable",
        "detail": last_error[:300],
        "attempts": attempts,
        "timeout_seconds": timeout,
        "probe": "deep",
    }


def rank_texts(profile_text: str, items: list[dict]) -> list[dict]:
    payload={
        "profile_text": (profile_text or "")[:500],
        "items": [{"id": int(x["id"]), "text": str(x.get("text", ""))[:500]} for x in items[:60]],
    }
    r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
        _base()+"/ai/rank", json=payload, headers=_headers(), timeout=_timeout()
    )
    r.raise_for_status()
    data=_json_object(r,"rank")
    rows=data.get("items",[])
    return rows if isinstance(rows,list) else []
