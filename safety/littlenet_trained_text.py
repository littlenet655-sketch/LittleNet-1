"""LittleNet's trained 18+ text-safety classifier interface.

The user trains and stages the text checkpoint; this module is the single
integration point between that private artifact and ``text_service.check_text``.
It is auto-enabled only when the artifact exists. When the artifact is absent
(or fails to load), callers fall back to the deterministic + Detoxify stack
already in ``text_service``. This lets code deploy safely before the private
model artifact is staged, and lets policy stay fail-closed either way.

Expected artifact
-----------------
A Hugging Face ``text-classification`` directory (the standard export for a
fine-tuned text classifier)::

    littlenet_text_safety/
        config.json
        tokenizer.json          (or tokenizer_config.json + vocab files)
        model.safetensors       (or pytorch_model.bin / model.onnx is NOT supported)

Placement (first existing location wins):
1. ``$LITTLENET_TRAINED_TEXT_PATH`` when set,
2. ``/cache/models/littlenet_text_safety`` (persistent Modal model-cache volume),
3. ``<repo>/models/littlenet_text_safety`` (local dev / test staging).

Label contract
--------------
``predict()`` maps the classifier's raw labels to LittleNet's signal envelope
by keyword matching on the label text (case-insensitive):

- sexual/explicit/porn/nsfw/adult/erotic/nudity  -> ``sexual_score``
- violence/violent/threat/kill                  -> ``violence_score``
- toxic/hate/harass/bully/abuse/self-harm       -> ``toxicity_score``

``sexual_score`` feeds the same ``adult >= 0.40`` hard-block path in
``policy.decide`` as every other 18+ text signal, so a flagged text is
blocked/held server-side exactly like a keyword or Detoxify hit.
"""
from __future__ import annotations

import os
import threading
from pathlib import Path
from typing import Any

_DEFAULT_DIR = "/cache/models/littlenet_text_safety"
_REPO_ROOT = Path(__file__).resolve().parent.parent

_LOCK = threading.Lock()
_PIPELINE: Any | None = None
_PIPELINE_PATH: Path | None = None

#: Maximum characters sent to the classifier (bounded inference cost).
MAX_CHARS = 2000

_SEXUAL_HINTS = ("sexual", "explicit", "porn", "nsfw", "adult", "erotic", "nudity", "nude")
_VIOLENCE_HINTS = ("violence", "violent", "threat", "kill")
_TOXIC_HINTS = ("toxic", "hate", "harass", "bully", "abuse", "self-harm", "self_harm")


def _flag(name: str, default: bool = True) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on", "auto"}


def _candidates() -> list[Path]:
    raw = (os.getenv("LITTLENET_TRAINED_TEXT_PATH") or "").strip()
    if raw:
        return [Path(raw)]
    return [
        Path(_DEFAULT_DIR),
        _REPO_ROOT / "models" / "littlenet_text_safety",
        Path("models") / "littlenet_text_safety",
    ]


def path() -> Path:
    """Return the artifact location: first existing candidate, else the default."""
    for candidate in _candidates():
        try:
            if candidate.is_dir() and any(candidate.iterdir()):
                return candidate
            if candidate.is_file() and candidate.stat().st_size > 0:
                return candidate
        except OSError:
            continue
    return Path(_DEFAULT_DIR)


def available() -> bool:
    """True only when the trained text artifact is staged and enabled."""
    if not _flag("LITTLENET_ENABLE_TRAINED_TEXT", True):
        return False
    artifact = path()
    try:
        if artifact.is_dir():
            # A Hugging Face classifier directory must carry at least a config.
            return (artifact / "config.json").is_file()
        return artifact.is_file() and artifact.stat().st_size > 0
    except OSError:
        return False


def _load_pipeline(artifact: Path):
    from transformers import pipeline

    if not artifact.is_dir():
        raise RuntimeError(
            "trained_text_unsupported_format: expected a Hugging Face "
            f"text-classification directory at {artifact}; got a single file. "
            "Export the fine-tuned classifier with "
            "model.save_pretrained('littlenet_text_safety') and "
            "tokenizer.save_pretrained('littlenet_text_safety'), then stage the "
            "directory at /cache/models/littlenet_text_safety (or set "
            "LITTLENET_TRAINED_TEXT_PATH)."
        )
    try:
        return pipeline(
            "text-classification",
            model=str(artifact),
            tokenizer=str(artifact),
            top_k=None,
            truncation=True,
            max_length=512,
            device=-1,
        )
    except Exception as exc:
        raise RuntimeError(f"trained_text_load_failed: {type(exc).__name__}: {exc}") from exc


def _pipeline():
    global _PIPELINE, _PIPELINE_PATH
    if _PIPELINE is not None:
        return _PIPELINE
    if not available():
        raise RuntimeError("trained_text_model_not_staged")
    artifact = path()
    with _LOCK:
        if _PIPELINE is None or _PIPELINE_PATH != artifact:
            _PIPELINE = _load_pipeline(artifact)
            _PIPELINE_PATH = artifact
    return _PIPELINE


def _bucket_scores(rows: list[dict[str, Any]]) -> dict[str, float]:
    sexual = violence = toxic = 0.0
    labels: dict[str, float] = {}
    for row in rows or []:
        label = str(row.get("label", "")).lower()
        try:
            score = float(row.get("score", 0) or 0)
        except (TypeError, ValueError):
            continue
        score = max(0.0, min(1.0, score))
        labels[label] = max(labels.get(label, 0.0), score)
        if any(hint in label for hint in _SEXUAL_HINTS):
            sexual = max(sexual, score)
        if any(hint in label for hint in _VIOLENCE_HINTS):
            violence = max(violence, score)
        if any(hint in label for hint in _TOXIC_HINTS):
            toxic = max(toxic, score)
    return {"sexual": sexual, "violence": violence, "toxic": toxic, "labels": labels}


def predict(text: str) -> dict[str, Any]:
    """Return LittleNet signal envelope for ``text`` from the trained classifier."""
    pipe = _pipeline()
    snippet = (text or "").strip()[:MAX_CHARS]
    if not snippet:
        raise RuntimeError("trained_text_empty_input")
    rows = pipe(snippet)
    if rows and isinstance(rows[0], list):
        rows = rows[0]
    buckets = _bucket_scores(rows if isinstance(rows, list) else [])

    sexual = buckets["sexual"]
    violence = buckets["violence"]
    toxic = buckets["toxic"]
    general = max(sexual, violence, toxic)
    category = (
        "SEXUAL_LANGUAGE"
        if sexual >= 0.40
        else ("SEVERE_ABUSE" if violence >= 0.60 else "TEXT")
    )
    return {
        "adult_score": sexual,
        "sexual_score": sexual,
        "violence_score": violence,
        "weapon_score": 0.0,
        "toxicity_score": toxic,
        "general_score": general,
        "category": category,
        "total_safety_failure": False,
        "partial_safety_failure": False,
        "errors": [],
        "model_signals": {
            "littlenet_trained_text": {
                "labels": buckets["labels"],
                "buckets": {
                    "sexual": sexual,
                    "violence": violence,
                    "toxic": toxic,
                },
                "source": {"path": path().name},
            }
        },
        "trained_text_model": True,
    }


def reset_for_tests() -> None:
    global _PIPELINE, _PIPELINE_PATH
    _PIPELINE = None
    _PIPELINE_PATH = None
