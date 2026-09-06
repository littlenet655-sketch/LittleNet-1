"""Client for the optional split LittleNet AI inference service.

The web app can run with only the lightweight dependencies and delegate heavy
inference (YOLO/NSFW/DeepFace/semantic ranking) to the protected AI service.
Every network request has a centrally bounded timeout and fails closed in its
caller when the AI service is unavailable.
"""
import json
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


def moderate_text(text: str) -> dict:
    r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
        _base() + "/ai/moderate",
        data={"content_type": "TEXT", "text": text or ""},
        headers=_headers(), timeout=_timeout(),
    )
    r.raise_for_status()
    return r.json()["signals"]


def moderate_file(content_type: str, path: str) -> dict:
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/moderate",
            data={"content_type": content_type.upper()},
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    return r.json()["signals"]


def face_embedding(path: str) -> list[float]:
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/face/embedding",
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    data = r.json()
    if not data.get("ok"):
        raise ValueError(data.get("reason", "face_error"))
    return [float(x) for x in data["embedding"]]


def face_verify(reference, path: str) -> dict:
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/face/verify",
            data={"reference": json.dumps(reference)},
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    return r.json()


def face_adult_verify(path: str) -> dict:
    """Run guardian liveness + adult-age analysis on the heavy AI service."""
    with open(path, "rb") as fh:
        r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
            _base() + "/ai/face/adult",
            files={"file": (Path(path).name, fh)},
            headers=_headers(), timeout=_timeout(),
        )
    r.raise_for_status()
    data = r.json()
    if not data.get("ok"):
        return {
            "is_adult": False,
            "estimated_age": None,
            "method": "REMOTE_AI",
            "reason": data.get("reason", "adult_face_verification_failed"),
        }
    return data.get("result") or {
        "is_adult": False,
        "estimated_age": None,
        "method": "REMOTE_AI",
        "reason": "adult_face_verification_empty",
    }


def health() -> dict:
    r = requests.get(_base() + "/healthz", headers=_headers(), timeout=10)
    r.raise_for_status()
    return r.json()


def rank_texts(profile_text: str, items: list[dict]) -> list[dict]:
    payload={
        "profile_text": (profile_text or "")[:500],
        "items": [{"id": int(x["id"]), "text": str(x.get("text", ""))[:500]} for x in items[:60]],
    }
    r = requests.post(  # nosec B113 - timeout is explicitly bounded by _timeout()
        _base()+"/ai/rank", json=payload, headers=_headers(), timeout=_timeout()
    )
    r.raise_for_status()
    return r.json().get("items",[])
