"""Optional LittleNet trained text-safety model.

This module is deliberately additive. Existing deterministic rules + Detoxify stay
active unless LITTLENET_TRAINED_TEXT_MODE=enforce is explicitly selected.

Deployment bundle contract (private Modal volume, never Git):
  /cache/models/littlenet_text_safety/
    config.json
    model.safetensors OR pytorch_model.bin
    tokenizer.json OR vocab.txt (plus normal Hugging Face tokenizer files)
    littlenet_metadata.json

littlenet_metadata.json:
{
  "format": "huggingface_sequence_classification",
  "release": "text-v2-epoch3",
  "labels": ["..."],
  "thresholds": {"label": 0.5},
  "activation": "sigmoid",
  "max_length": 256,
  "signal_map": {"optional_label": "toxicity"}
}

Modes:
- off:    zero runtime effect; current LittleNet text stack is unchanged.
- shadow: execute when staged, but do not affect ALLOW/REVIEW/BLOCK.
- enforce: merge trained evidence into the existing LittleNet safety policy.
"""
from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from typing import Any

_DEFAULT_DIR = "/cache/models/littlenet_text_safety"
_METADATA_NAME = "littlenet_metadata.json"
_VALID_MODES = {"off", "shadow", "enforce"}
_VALID_SIGNALS = {"adult", "sexual", "violence", "weapon", "toxicity", "general"}

_LOCK = threading.Lock()
_RUNTIME: tuple[Any, Any, dict[str, Any]] | None = None


def mode() -> str:
    raw = (os.getenv("LITTLENET_TRAINED_TEXT_MODE") or "off").strip().lower()
    return raw if raw in _VALID_MODES else "off"


def bundle_dir() -> Path:
    return Path(os.getenv("LITTLENET_TRAINED_TEXT_PATH", _DEFAULT_DIR))


def metadata_path() -> Path:
    return bundle_dir() / _METADATA_NAME


def _weights_exist(root: Path) -> bool:
    return any((root / name).is_file() and (root / name).stat().st_size > 0 for name in (
        "model.safetensors",
        "pytorch_model.bin",
    ))


def _tokenizer_exists(root: Path) -> bool:
    return any((root / name).is_file() and (root / name).stat().st_size > 0 for name in (
        "tokenizer.json",
        "vocab.txt",
        "sentencepiece.bpe.model",
        "spiece.model",
    ))


def available() -> bool:
    root = bundle_dir()
    return bool(
        root.is_dir()
        and (root / "config.json").is_file()
        and metadata_path().is_file()
        and _weights_exist(root)
        and _tokenizer_exists(root)
    )


def _clean_label(value: Any) -> str:
    return " ".join(str(value or "").strip().lower().replace("_", " ").replace("-", " ").split())


def _load_metadata() -> dict[str, Any]:
    path = metadata_path()
    if not path.is_file():
        raise RuntimeError("trained_text_metadata_missing")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError("trained_text_metadata_invalid_json") from exc
    if not isinstance(raw, dict):
        raise RuntimeError("trained_text_metadata_invalid")

    fmt = str(raw.get("format") or "huggingface_sequence_classification").strip().lower()
    if fmt != "huggingface_sequence_classification":
        raise RuntimeError(f"trained_text_format_unsupported:{fmt}")

    labels = raw.get("labels")
    if not isinstance(labels, list) or not labels:
        raise RuntimeError("trained_text_labels_missing")
    cleaned = [_clean_label(x) for x in labels]
    if any(not x for x in cleaned) or len(set(cleaned)) != len(cleaned):
        raise RuntimeError("trained_text_labels_invalid")

    thresholds_raw = raw.get("thresholds") or {}
    if not isinstance(thresholds_raw, dict):
        raise RuntimeError("trained_text_thresholds_invalid")
    thresholds: dict[str, float] = {}
    for original, cleaned_label in zip(labels, cleaned):
        value = thresholds_raw.get(original, thresholds_raw.get(cleaned_label, 0.5))
        try:
            threshold = float(value)
        except (TypeError, ValueError) as exc:
            raise RuntimeError(f"trained_text_threshold_invalid:{cleaned_label}") from exc
        if not 0.01 <= threshold <= 0.99:
            raise RuntimeError(f"trained_text_threshold_out_of_range:{cleaned_label}")
        thresholds[cleaned_label] = threshold

    activation = str(raw.get("activation") or "sigmoid").strip().lower()
    if activation not in {"sigmoid", "softmax"}:
        raise RuntimeError("trained_text_activation_invalid")

    try:
        max_length = int(raw.get("max_length") or 256)
    except (TypeError, ValueError):
        max_length = 256
    max_length = max(32, min(max_length, 512))

    signal_map_raw = raw.get("signal_map") or {}
    if not isinstance(signal_map_raw, dict):
        raise RuntimeError("trained_text_signal_map_invalid")
    signal_map: dict[str, str] = {}
    for label, signal in signal_map_raw.items():
        cleaned_label = _clean_label(label)
        cleaned_signal = str(signal or "").strip().lower()
        if cleaned_label and cleaned_signal in _VALID_SIGNALS:
            signal_map[cleaned_label] = cleaned_signal

    release = str(raw.get("release") or raw.get("version") or bundle_dir().name).strip()[:80]
    return {
        **raw,
        "format": fmt,
        "labels": cleaned,
        "thresholds": thresholds,
        "activation": activation,
        "max_length": max_length,
        "signal_map": signal_map,
        "release": release or "unknown",
    }


def _runtime():
    global _RUNTIME
    if _RUNTIME is not None:
        return _RUNTIME
    if not available():
        raise RuntimeError("trained_text_bundle_not_staged")
    with _LOCK:
        if _RUNTIME is None:
            from transformers import AutoModelForSequenceClassification, AutoTokenizer

            root = bundle_dir()
            metadata = _load_metadata()
            tokenizer = AutoTokenizer.from_pretrained(str(root), local_files_only=True)
            model = AutoModelForSequenceClassification.from_pretrained(str(root), local_files_only=True)
            model.eval()

            num_labels = int(getattr(model.config, "num_labels", 0) or 0)
            if num_labels != len(metadata["labels"]):
                raise RuntimeError(
                    f"trained_text_label_count_mismatch:model={num_labels}:metadata={len(metadata['labels'])}"
                )
            _RUNTIME = (tokenizer, model, metadata)
    return _RUNTIME


def _default_signal(label: str) -> str:
    low = _clean_label(label)
    if any(term in low for term in ("nudity", "nude", "sexual", "sex", "porn", "explicit", "adult", "sexy")):
        return "sexual"
    if any(term in low for term in ("weapon", "gun", "knife", "firearm")):
        return "weapon"
    if any(term in low for term in ("violence", "violent", "physical threat")):
        return "violence"
    if any(term in low for term in ("toxic", "bully", "harass", "hate", "abuse", "insult", "profan")):
        return "toxicity"
    return "general"


def _signals_from_scores(scores: dict[str, float], metadata: dict[str, Any]) -> dict[str, Any]:
    labels = list(metadata["labels"])
    thresholds = dict(metadata["thresholds"])
    explicit_map = dict(metadata.get("signal_map") or {})

    triggered = {label: float(scores.get(label, 0.0)) >= float(thresholds[label]) for label in labels}
    values = {
        "adult_score": 0.0,
        "sexual_score": 0.0,
        "violence_score": 0.0,
        "weapon_score": 0.0,
        "toxicity_score": 0.0,
        "general_score": 0.0,
    }

    top_label = None
    top_score = 0.0
    for label in labels:
        probability = max(0.0, min(1.0, float(scores.get(label, 0.0) or 0.0)))
        if not triggered[label]:
            continue
        signal = explicit_map.get(label) or _default_signal(label)
        if probability > top_score:
            top_score = probability
            top_label = label

        if signal in {"adult", "sexual"}:
            values["adult_score"] = max(values["adult_score"], probability)
            values["sexual_score"] = max(values["sexual_score"], probability)
        elif signal == "violence":
            values["violence_score"] = max(values["violence_score"], probability)
        elif signal == "weapon":
            values["weapon_score"] = max(values["weapon_score"], probability)
        elif signal == "toxicity":
            values["toxicity_score"] = max(values["toxicity_score"], probability)
        values["general_score"] = max(values["general_score"], probability)

    if values["adult_score"] > 0:
        category = "SEXUAL_LANGUAGE"
    elif values["weapon_score"] > 0:
        category = "WEAPON"
    elif top_label:
        category = "TEXT"
    else:
        category = "TEXT"

    return {
        **values,
        "category": category,
        "total_safety_failure": False,
        "partial_safety_failure": False,
        "errors": [],
        "model_signals": {
            "littlenet_trained_text": {
                "release": metadata.get("release") or "unknown",
                "probabilities": {k: float(scores.get(k, 0.0) or 0.0) for k in labels},
                "thresholds": thresholds,
                "triggered": triggered,
                "top_triggered_label": top_label,
            }
        },
        "trained_text_model": True,
        "trained_text_release": metadata.get("release") or "unknown",
    }


def predict(text: str) -> dict[str, Any]:
    tokenizer, model, metadata = _runtime()
    import torch

    encoded = tokenizer(
        (text or "")[:8000],
        return_tensors="pt",
        truncation=True,
        max_length=int(metadata["max_length"]),
        padding=False,
    )
    with torch.inference_mode():
        output = model(**encoded)
        logits = output.logits[0]
        if metadata["activation"] == "softmax":
            probabilities = torch.softmax(logits, dim=-1).cpu().tolist()
        else:
            probabilities = torch.sigmoid(logits).cpu().tolist()

    labels = list(metadata["labels"])
    scores = {label: float(probabilities[i]) for i, label in enumerate(labels)}
    return _signals_from_scores(scores, metadata)


def preflight() -> dict[str, Any]:
    root = bundle_dir()
    report: dict[str, Any] = {
        "mode": mode(),
        "path": str(root),
        "available": available(),
        "metadata_exists": metadata_path().is_file(),
        "weights_present": _weights_exist(root) if root.is_dir() else False,
        "tokenizer_present": _tokenizer_exists(root) if root.is_dir() else False,
        "loadable": False,
    }
    if not report["available"]:
        return report
    try:
        metadata = _load_metadata()
        result = predict("Hello, this is a normal LittleNet safety preflight sentence.")
        report.update({
            "loadable": True,
            "release": metadata.get("release"),
            "labels": list(metadata.get("labels") or []),
            "thresholds": dict(metadata.get("thresholds") or {}),
            "sample_total_failure": bool(result.get("total_safety_failure")),
        })
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
    return report


def reset_for_tests() -> None:
    global _RUNTIME
    _RUNTIME = None
