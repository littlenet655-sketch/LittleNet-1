"""Optional LittleNet trained text-safety model.

The adapter is deliberately additive: deterministic LittleNet rules + Detoxify
remain authoritative unless LITTLENET_TRAINED_TEXT_MODE=enforce is explicitly
selected.

Current trained V2 bundle (preferred):
  /cache/models/littlenet_text_safety/
    littlenet_text_model.pt
    metadata.json
    dual_threshold_policy.json and/or thresholds_validation.json
    tokenizer files
    encoder/                 # saved multilingual DistilBERT encoder/config

The current V2 architecture is:
  distilbert/distilbert-base-multilingual-cased AutoModel
  first-token embedding -> Dropout(0.20) -> Linear(hidden_size, 13)

A standard Hugging Face sequence-classification bundle is also supported for
future versions.

Modes:
- off:    exact current behavior; trained model is not loaded.
- shadow: run trained inference for diagnostics only.
- enforce: merge trained evidence into the existing LittleNet policy.
"""
from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from typing import Any

_DEFAULT_DIR = "/cache/models/littlenet_text_safety"
_METADATA_CANDIDATES = ("littlenet_metadata.json", "metadata.json")
_CUSTOM_MODEL = "littlenet_text_model.pt"
_CUSTOM_ENCODER_DIR = "encoder"
_VALID_MODES = {"off", "shadow", "enforce"}
_VALID_SIGNALS = {"adult", "sexual", "violence", "weapon", "toxicity", "general", "ignore"}

# Frozen label order from the final LittleNet V2 training pipeline.
_CURRENT_V2_LABELS = [
    "sexual",
    "grooming",
    "bullying",
    "hate",
    "violence",
    "self harm",
    "drugs",
    "alcohol",
    "smoking",
    "gambling",
    "profanity",
    "pii request",
    "contact request",
]

# Frozen FINAL V2 dual-threshold policy. Uploaded policy JSON overrides these
# values; this fallback prevents an accidental generic 0.5 deployment if the
# JSON shape changes while the verified checkpoint itself is unchanged.
_CURRENT_V2_REVIEW_THRESHOLDS = {
    "sexual": 0.080,
    "grooming": 0.955,
    "bullying": 0.495,
    "hate": 0.660,
    "violence": 0.050,
    "self harm": 0.750,
    "drugs": 0.160,
    "alcohol": 0.510,
    "smoking": 0.315,
    "gambling": 0.250,
    "profanity": 0.725,
    "pii request": 0.965,
    "contact request": 0.925,
}
_CURRENT_V2_BLOCK_THRESHOLDS = {
    "sexual": 0.950,
    "grooming": 0.955,
    "bullying": 0.640,
    "hate": 0.960,
    "violence": 0.985,
    "self harm": 0.750,
    "drugs": 0.160,
    "alcohol": 0.510,
    "smoking": 0.315,
    "gambling": 0.250,
    "profanity": 0.960,
    "pii request": 0.965,
    "contact request": 0.925,
}

_LOCK = threading.Lock()
_RUNTIME: tuple[Any, Any, dict[str, Any]] | None = None


def mode() -> str:
    raw = (os.getenv("LITTLENET_TRAINED_TEXT_MODE") or "off").strip().lower()
    return raw if raw in _VALID_MODES else "off"


def bundle_dir() -> Path:
    return Path(os.getenv("LITTLENET_TRAINED_TEXT_PATH", _DEFAULT_DIR))


def _metadata_path(root: Path | None = None) -> Path:
    root = root or bundle_dir()
    for name in _METADATA_CANDIDATES:
        candidate = root / name
        if candidate.is_file():
            return candidate
    return root / _METADATA_CANDIDATES[0]


def metadata_path() -> Path:
    return _metadata_path()


def _tokenizer_exists(root: Path) -> bool:
    return any((root / name).is_file() and (root / name).stat().st_size > 0 for name in (
        "tokenizer.json",
        "tokenizer_config.json",
        "vocab.txt",
        "sentencepiece.bpe.model",
        "spiece.model",
    ))


def _hf_weights_exist(root: Path) -> bool:
    return any((root / name).is_file() and (root / name).stat().st_size > 0 for name in (
        "model.safetensors",
        "pytorch_model.bin",
    ))


def _custom_bundle_available(root: Path) -> bool:
    return bool(
        (root / _CUSTOM_MODEL).is_file()
        and (root / _CUSTOM_MODEL).stat().st_size > 0
        and (root / _CUSTOM_ENCODER_DIR).is_dir()
        and (root / _CUSTOM_ENCODER_DIR / "config.json").is_file()
        and _metadata_path(root).is_file()
        and _tokenizer_exists(root)
    )


def _hf_bundle_available(root: Path) -> bool:
    return bool(
        (root / "config.json").is_file()
        and _metadata_path(root).is_file()
        and _hf_weights_exist(root)
        and _tokenizer_exists(root)
    )


def available() -> bool:
    root = bundle_dir()
    return root.is_dir() and (_custom_bundle_available(root) or _hf_bundle_available(root))


def _clean_label(value: Any) -> str:
    return " ".join(str(value or "").strip().lower().replace("_", " ").replace("-", " ").split())


def _json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"trained_text_invalid_json:{path.name}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"trained_text_invalid_mapping:{path.name}")
    return value


def _extract_labels(raw: dict[str, Any]) -> list[str]:
    candidates = (
        raw.get("labels"),
        raw.get("label_names"),
        raw.get("LABELS"),
    )
    labels = next((x for x in candidates if isinstance(x, list) and x), None)
    if not labels:
        id2label = raw.get("id2label")
        if isinstance(id2label, dict) and id2label:
            try:
                labels = [id2label[str(i)] if str(i) in id2label else id2label[i] for i in range(len(id2label))]
            except Exception:
                labels = None
    if not labels:
        # The final V2 artifact uses this frozen order. Keep it as a compatibility
        # fallback only for the known custom checkpoint layout.
        if (bundle_dir() / _CUSTOM_MODEL).is_file():
            labels = list(_CURRENT_V2_LABELS)
        else:
            raise RuntimeError("trained_text_labels_missing")
    cleaned = [_clean_label(x) for x in labels]
    if any(not x for x in cleaned) or len(set(cleaned)) != len(cleaned):
        raise RuntimeError("trained_text_labels_invalid")
    return cleaned


def _coerce_threshold_map(value: Any, labels: list[str]) -> dict[str, float]:
    if not isinstance(value, dict):
        return {}
    out: dict[str, float] = {}
    for label in labels:
        raw = value.get(label)
        if raw is None:
            raw = value.get(label.replace(" ", "_"))
        if raw is None:
            continue
        try:
            threshold = float(raw)
        except (TypeError, ValueError):
            continue
        if 0.0 <= threshold <= 1.0:
            out[label] = threshold
    return out


def _threshold_maps(root: Path, raw: dict[str, Any], labels: list[str]) -> tuple[dict[str, float], dict[str, float]]:
    review: dict[str, float] = {}
    block: dict[str, float] = {}

    # Common metadata shapes.
    for key in ("review_thresholds", "thresholds", "deployment_thresholds"):
        review.update(_coerce_threshold_map(raw.get(key), labels))
    block.update(_coerce_threshold_map(raw.get("block_thresholds"), labels))

    # Final V2/V4 style dual-threshold policy file.
    dual_path = root / "dual_threshold_policy.json"
    if dual_path.is_file():
        dual = _json(dual_path)
        for key in ("review", "review_thresholds", "review_layer", "allow_review_thresholds"):
            review.update(_coerce_threshold_map(dual.get(key), labels))
        for key in ("block", "block_thresholds", "block_layer"):
            block.update(_coerce_threshold_map(dual.get(key), labels))
        per_label = dual.get("labels")
        if isinstance(per_label, dict):
            for label in labels:
                spec = per_label.get(label) or per_label.get(label.replace(" ", "_"))
                if not isinstance(spec, dict):
                    continue
                try:
                    if "review" in spec:
                        review[label] = float(spec["review"])
                    if "block" in spec:
                        block[label] = float(spec["block"])
                except (TypeError, ValueError):
                    pass

    single_path = root / "thresholds_validation.json"
    if single_path.is_file():
        single = _json(single_path)
        for key in ("thresholds", "validation_thresholds", "deployment_thresholds"):
            review.update(_coerce_threshold_map(single.get(key), labels))
        # Some exports are a direct label -> threshold mapping.
        review.update(_coerce_threshold_map(single, labels))

    # For the verified FINAL V2 custom artifact, use the frozen deployment policy
    # as a fallback. Other/future formats retain a conservative 0.5 review default.
    is_final_v2 = (root / _CUSTOM_MODEL).is_file() and set(labels) == set(_CURRENT_V2_LABELS)
    review = {
        label: max(
            0.01,
            min(
                0.99,
                float(
                    review.get(
                        label,
                        _CURRENT_V2_REVIEW_THRESHOLDS.get(label, 0.5) if is_final_v2 else 0.5,
                    )
                ),
            ),
        )
        for label in labels
    }
    if is_final_v2:
        for label, threshold in _CURRENT_V2_BLOCK_THRESHOLDS.items():
            block.setdefault(label, threshold)

    clean_block: dict[str, float] = {}
    for label, value in block.items():
        try:
            threshold = float(value)
        except (TypeError, ValueError):
            continue
        if 0.01 <= threshold <= 0.99:
            clean_block[label] = threshold
    return review, clean_block


def _load_metadata() -> dict[str, Any]:
    root = bundle_dir()
    path = _metadata_path(root)
    if not path.is_file():
        raise RuntimeError("trained_text_metadata_missing")
    raw = _json(path)
    labels = _extract_labels(raw)
    review_thresholds, block_thresholds = _threshold_maps(root, raw, labels)

    fmt = str(raw.get("format") or "").strip().lower()
    if _custom_bundle_available(root):
        fmt = "littlenet_v2_custom_distilbert"
    elif not fmt:
        fmt = "huggingface_sequence_classification"

    try:
        max_length = int(raw.get("max_length") or (128 if fmt == "littlenet_v2_custom_distilbert" else 256))
    except (TypeError, ValueError):
        max_length = 128 if fmt == "littlenet_v2_custom_distilbert" else 256
    max_length = max(32, min(max_length, 512))

    try:
        dropout = float(raw.get("dropout") or raw.get("dropout_probability") or 0.20)
    except (TypeError, ValueError):
        dropout = 0.20
    dropout = max(0.0, min(dropout, 0.8))

    activation = str(raw.get("activation") or "sigmoid").strip().lower()
    if activation not in {"sigmoid", "softmax"}:
        activation = "sigmoid"

    signal_map_raw = raw.get("signal_map") or {}
    if not isinstance(signal_map_raw, dict):
        signal_map_raw = {}
    signal_map: dict[str, str] = {}
    for label, signal in signal_map_raw.items():
        cleaned_label = _clean_label(label)
        cleaned_signal = str(signal or "").strip().lower()
        if cleaned_label and cleaned_signal in _VALID_SIGNALS:
            signal_map[cleaned_label] = cleaned_signal

    release = str(
        raw.get("release")
        or raw.get("version")
        or raw.get("checkpoint_name")
        or raw.get("checkpoint_epoch")
        or raw.get("epoch")
        or root.name
    ).strip()[:80]

    return {
        **raw,
        "format": fmt,
        "labels": labels,
        "review_thresholds": review_thresholds,
        "block_thresholds": block_thresholds,
        "activation": activation,
        "max_length": max_length,
        "dropout": dropout,
        "signal_map": signal_map,
        "release": release or "unknown",
    }


def _state_dict_from_checkpoint(checkpoint: Any) -> dict[str, Any]:
    if not isinstance(checkpoint, dict):
        raise RuntimeError("trained_text_checkpoint_invalid")
    for key in ("model_state_dict", "state_dict", "best_state", "model"):
        value = checkpoint.get(key)
        if isinstance(value, dict) and value:
            checkpoint = value
            break
    if not checkpoint or not all(isinstance(k, str) for k in checkpoint):
        raise RuntimeError("trained_text_state_dict_missing")
    clean: dict[str, Any] = {}
    for key, value in checkpoint.items():
        name = key[7:] if key.startswith("module.") else key
        clean[name] = value
    return clean


def _build_custom_runtime(root: Path, metadata: dict[str, Any]):
    import torch
    import torch.nn as nn
    from transformers import AutoModel, AutoTokenizer

    class LittleNetTextSafetyModel(nn.Module):
        def __init__(self):
            super().__init__()
            self.encoder = AutoModel.from_pretrained(str(root / _CUSTOM_ENCODER_DIR), local_files_only=True)
            hidden = int(getattr(self.encoder.config, "hidden_size", 0) or getattr(self.encoder.config, "dim", 0))
            if hidden <= 0:
                raise RuntimeError("trained_text_hidden_size_missing")
            self.dropout = nn.Dropout(float(metadata["dropout"]))
            self.classifier = nn.Linear(hidden, len(metadata["labels"]))

        def forward(self, input_ids=None, attention_mask=None, **kwargs):
            outputs = self.encoder(input_ids=input_ids, attention_mask=attention_mask, **kwargs)
            first_token = outputs.last_hidden_state[:, 0, :]
            return self.classifier(self.dropout(first_token))

    tokenizer = AutoTokenizer.from_pretrained(str(root), local_files_only=True)
    model = LittleNetTextSafetyModel()
    checkpoint = torch.load(root / _CUSTOM_MODEL, map_location="cpu", weights_only=True)
    state_dict = _state_dict_from_checkpoint(checkpoint)
    try:
        model.load_state_dict(state_dict, strict=True)
    except RuntimeError as exc:
        raise RuntimeError(f"trained_text_state_dict_mismatch:{exc}") from exc
    model.eval()
    return tokenizer, model


def _build_hf_runtime(root: Path, metadata: dict[str, Any]):
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(str(root), local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(str(root), local_files_only=True)
    model.eval()
    num_labels = int(getattr(model.config, "num_labels", 0) or 0)
    if num_labels != len(metadata["labels"]):
        raise RuntimeError(
            f"trained_text_label_count_mismatch:model={num_labels}:metadata={len(metadata['labels'])}"
        )
    return tokenizer, model


def _runtime():
    global _RUNTIME
    if _RUNTIME is not None:
        return _RUNTIME
    if not available():
        raise RuntimeError("trained_text_bundle_not_staged")
    with _LOCK:
        if _RUNTIME is None:
            root = bundle_dir()
            metadata = _load_metadata()
            if metadata["format"] == "littlenet_v2_custom_distilbert":
                tokenizer, model = _build_custom_runtime(root, metadata)
            elif metadata["format"] == "huggingface_sequence_classification":
                tokenizer, model = _build_hf_runtime(root, metadata)
            else:
                raise RuntimeError(f"trained_text_format_unsupported:{metadata['format']}")
            _RUNTIME = (tokenizer, model, metadata)
    return _RUNTIME


def _default_signal(label: str) -> str:
    low = _clean_label(label)
    if low in {"safe", "clean", "benign", "neutral", "appropriate", "normal"}:
        return "ignore"
    if any(term in low for term in ("sexual", "nudity", "nude", "porn", "explicit", "adult", "sexy")):
        return "sexual"
    if any(term in low for term in ("weapon", "gun", "knife", "firearm")):
        return "weapon"
    if "violence" in low or "violent" in low:
        return "violence"
    if any(term in low for term in ("bully", "hate", "profan", "toxic", "harass", "abuse", "insult")):
        return "toxicity"
    return "general"


def _label_state(probability: float, review_threshold: float, block_threshold: float | None) -> str:
    if block_threshold is not None and probability >= block_threshold:
        return "block"
    if probability >= review_threshold:
        return "review"
    return "clear"


def _signals_from_scores(scores: dict[str, float], metadata: dict[str, Any]) -> dict[str, Any]:
    labels = list(metadata["labels"])
    review_thresholds = dict(metadata.get("review_thresholds") or metadata.get("thresholds") or {})
    block_thresholds = dict(metadata.get("block_thresholds") or {})
    explicit_map = dict(metadata.get("signal_map") or {})

    states: dict[str, str] = {}
    triggered: dict[str, bool] = {}
    values = {
        "adult_score": 0.0,
        "sexual_score": 0.0,
        "violence_score": 0.0,
        "weapon_score": 0.0,
        "toxicity_score": 0.0,
        "general_score": 0.0,
    }
    top_label = None
    top_probability = 0.0

    for label in labels:
        probability = max(0.0, min(1.0, float(scores.get(label, 0.0) or 0.0)))
        review_t = float(review_thresholds.get(label, 0.5))
        block_raw = block_thresholds.get(label)
        block_t = float(block_raw) if block_raw is not None else None
        state = _label_state(probability, review_t, block_t)
        states[label] = state
        triggered[label] = state != "clear"
        if state == "clear":
            continue

        signal = explicit_map.get(label) or _default_signal(label)
        if signal == "ignore":
            continue
        if probability > top_probability:
            top_probability = probability
            top_label = label

        # Trained thresholds are calibrated in model-probability space while the
        # central LittleNet policy uses policy-risk space. Translate threshold
        # crossing, rather than comparing raw probabilities to unrelated policy
        # thresholds.
        policy_risk = 0.80 if state == "block" else 0.50

        if signal in {"adult", "sexual"}:
            if state == "block":
                values["adult_score"] = max(values["adult_score"], 0.80)
                values["sexual_score"] = max(values["sexual_score"], 0.80)
            else:
                # Stay below the global adult hard-block boundary while still
                # sending the item to REVIEW through general_score.
                values["adult_score"] = max(values["adult_score"], 0.39)
                values["sexual_score"] = max(values["sexual_score"], 0.39)
        elif signal == "violence":
            values["violence_score"] = max(values["violence_score"], policy_risk)
        elif signal == "weapon":
            values["weapon_score"] = max(values["weapon_score"], 0.80 if state == "block" else 0.39)
        elif signal == "toxicity":
            values["toxicity_score"] = max(values["toxicity_score"], policy_risk)

        values["general_score"] = max(values["general_score"], policy_risk)

    category = "TEXT"
    if values["adult_score"] >= 0.40:
        category = "SEXUAL_LANGUAGE"
    elif values["weapon_score"] >= 0.45:
        category = "WEAPON"

    return {
        **values,
        "category": category,
        "total_safety_failure": False,
        "partial_safety_failure": False,
        "errors": [],
        "model_signals": {
            "littlenet_trained_text": {
                "release": metadata.get("release") or "unknown",
                "format": metadata.get("format"),
                "probabilities": {k: float(scores.get(k, 0.0) or 0.0) for k in labels},
                "review_thresholds": review_thresholds,
                "block_thresholds": block_thresholds,
                "states": states,
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
        logits = output.logits[0] if hasattr(output, "logits") else output[0]
        if metadata["activation"] == "softmax":
            probabilities = torch.softmax(logits, dim=-1).cpu().tolist()
        else:
            probabilities = torch.sigmoid(logits).cpu().tolist()

    labels = list(metadata["labels"])
    if len(probabilities) != len(labels):
        raise RuntimeError("trained_text_probability_count_mismatch")
    scores = {label: float(probabilities[i]) for i, label in enumerate(labels)}
    return _signals_from_scores(scores, metadata)


def preflight() -> dict[str, Any]:
    root = bundle_dir()
    report: dict[str, Any] = {
        "mode": mode(),
        "path": str(root),
        "available": available(),
        "custom_v2_layout": _custom_bundle_available(root) if root.is_dir() else False,
        "hf_layout": _hf_bundle_available(root) if root.is_dir() else False,
        "metadata_exists": _metadata_path(root).is_file() if root.is_dir() else False,
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
            "format": metadata.get("format"),
            "labels": list(metadata.get("labels") or []),
            "review_thresholds": dict(metadata.get("review_thresholds") or {}),
            "block_thresholds": dict(metadata.get("block_thresholds") or {}),
            "max_length": int(metadata.get("max_length") or 0),
            "sample_total_failure": bool(result.get("total_safety_failure")),
        })
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
    return report


def reset_for_tests() -> None:
    global _RUNTIME
    _RUNTIME = None
