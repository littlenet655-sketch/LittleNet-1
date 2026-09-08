"""Client for the optional split LittleNet AI inference service.

The web app can run with only the lightweight dependencies and delegate heavy
inference (YOLO/NSFW/DeepFace/semantic ranking) to the protected AI service.
Every network request has a centrally bounded timeout and fails closed in its
caller when the AI service is unavailable.
"""
import json
import math
import os
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


def health() -> dict:
    r = requests.get(_base() + "/healthz", headers=_headers(), timeout=10)
    r.raise_for_status()
    return _json_object(r, "health")


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
