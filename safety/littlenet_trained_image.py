"""LittleNet's trained four-category image-safety ensemble.

The two checkpoints are staged on the persistent Modal model cache volume:
- V2: nudity + sexy (other V2 outputs are intentionally ignored)
- V3: weapons + violence

The ensemble is auto-enabled only when BOTH checkpoint files exist. If either
file is absent, callers fall back to the legacy detector stack. This lets code
deploy safely before the private model artifacts are staged.
"""
from __future__ import annotations

import os
import threading
from pathlib import Path
from typing import Any

_DEFAULT_V2 = "/cache/models/littlenet_core_safety_v2.pth"
_DEFAULT_V3 = "/cache/models/littlenet_weapons_violence_v3.pth"

_LOCK = threading.Lock()
_MODELS: tuple[Any, dict[str, Any], Any, dict[str, Any]] | None = None


def _flag(name: str, default: bool = True) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on", "auto"}


def paths() -> tuple[Path, Path]:
    return (
        Path(os.getenv("LITTLENET_TRAINED_IMAGE_V2_PATH", _DEFAULT_V2)),
        Path(os.getenv("LITTLENET_TRAINED_IMAGE_V3_PATH", _DEFAULT_V3)),
    )


def available() -> bool:
    if not _flag("LITTLENET_ENABLE_TRAINED_IMAGE_ENSEMBLE", True):
        return False
    v2, v3 = paths()
    return v2.is_file() and v3.is_file() and v2.stat().st_size > 0 and v3.stat().st_size > 0


def _load_one(path: Path):
    import torch
    import torch.nn as nn
    from torchvision.models import efficientnet_b0

    checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    if not isinstance(checkpoint, dict) or not isinstance(checkpoint.get("state_dict"), dict):
        raise RuntimeError(f"invalid LittleNet image checkpoint: {path.name}")
    labels = list(checkpoint.get("labels") or [])
    if not labels:
        raise RuntimeError(f"missing labels in LittleNet image checkpoint: {path.name}")

    model = efficientnet_b0(weights=None)
    in_features = model.classifier[1].in_features
    model.classifier[1] = nn.Linear(in_features, len(labels))
    model.load_state_dict(checkpoint["state_dict"], strict=True)
    model.eval()
    return model, checkpoint


def _models():
    global _MODELS
    if _MODELS is not None:
        return _MODELS
    if not available():
        raise RuntimeError("trained_image_ensemble_not_staged")
    with _LOCK:
        if _MODELS is None:
            v2_path, v3_path = paths()
            v2_model, v2_ckpt = _load_one(v2_path)
            v3_model, v3_ckpt = _load_one(v3_path)
            required_v2 = {"nudity", "sexy"}
            required_v3 = {"weapons", "violence"}
            if not required_v2.issubset(set(v2_ckpt.get("labels") or [])):
                raise RuntimeError("V2 checkpoint missing nudity/sexy labels")
            if not required_v3.issubset(set(v3_ckpt.get("labels") or [])):
                raise RuntimeError("V3 checkpoint missing weapons/violence labels")
            _MODELS = (v2_model, v2_ckpt, v3_model, v3_ckpt)
    return _MODELS


def _transform(image_path: str):
    from PIL import Image
    from torchvision import transforms

    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(
            [0.485, 0.456, 0.406],
            [0.229, 0.224, 0.225],
        ),
    ])
    return transform(Image.open(image_path).convert("RGB")).unsqueeze(0)


def _scores(model, checkpoint: dict[str, Any], tensor) -> dict[str, float]:
    import torch

    with torch.inference_mode():
        probs = torch.sigmoid(model(tensor))[0].cpu().tolist()
    labels = list(checkpoint["labels"])
    return {label: float(probs[i]) for i, label in enumerate(labels)}


def _threshold(checkpoint: dict[str, Any], label: str, fallback: float) -> float:
    raw = (checkpoint.get("thresholds") or {}).get(label, fallback)
    try:
        value = float(raw)
    except (TypeError, ValueError):
        value = fallback
    return max(0.01, min(0.99, value))


def _below_threshold_score(probability: float, threshold: float, ceiling: float) -> float:
    # Preserve the tuned per-class threshold: a sub-threshold probability must
    # never be promoted into a policy hard-block solely because the global
    # LittleNet policy threshold uses a different numerical scale.
    ratio = max(0.0, min(1.0, probability / max(threshold, 1e-6)))
    return min(ceiling, ratio * ceiling)


def predict(image_path: str) -> dict[str, Any]:
    """Return raw probabilities plus policy-calibrated LittleNet safety signals."""
    v2_model, v2_ckpt, v3_model, v3_ckpt = _models()
    tensor = _transform(image_path)

    v2 = _scores(v2_model, v2_ckpt, tensor)
    v3 = _scores(v3_model, v3_ckpt, tensor)

    thresholds = {
        "nudity": _threshold(v2_ckpt, "nudity", 0.89),
        "sexy": _threshold(v2_ckpt, "sexy", 0.82),
        "weapons": _threshold(v3_ckpt, "weapons", 0.59),
        "violence": _threshold(v3_ckpt, "violence", 0.49),
    }
    raw = {
        "nudity": float(v2["nudity"]),
        "sexy": float(v2["sexy"]),
        "weapons": float(v3["weapons"]),
        "violence": float(v3["violence"]),
    }
    triggered = {name: raw[name] >= thresholds[name] for name in raw}

    sexual_triggered = triggered["nudity"] or triggered["sexy"]
    if sexual_triggered:
        adult_score = max(0.80, raw["nudity"], raw["sexy"])
    else:
        adult_score = max(
            _below_threshold_score(raw["nudity"], thresholds["nudity"], 0.39),
            _below_threshold_score(raw["sexy"], thresholds["sexy"], 0.39),
        )

    weapon_score = max(0.80, raw["weapons"]) if triggered["weapons"] else 0.0

    if triggered["violence"]:
        violence_score = max(0.80, raw["violence"])
    elif raw["violence"] >= 0.80 * thresholds["violence"]:
        # Near-threshold violence goes to parent review under STRICT policy,
        # while clearly sub-threshold frames stay out of the risk path.
        violence_score = 0.50
    else:
        violence_score = 0.0

    general = max(adult_score, weapon_score, violence_score)
    if sexual_triggered:
        category = "ADULT"
    elif triggered["weapons"]:
        category = "WEAPON"
    else:
        category = "IMAGE"

    return {
        "adult_score": adult_score,
        "sexual_score": adult_score,
        "violence_score": violence_score,
        "weapon_score": weapon_score,
        "toxicity_score": 0.0,
        "general_score": general,
        "category": category,
        "total_safety_failure": False,
        "partial_safety_failure": False,
        "errors": [],
        "model_signals": {
            "littlenet_trained_image": {
                "raw_probabilities": raw,
                "thresholds": thresholds,
                "triggered": triggered,
                "source": {
                    "v2": paths()[0].name,
                    "v3": paths()[1].name,
                },
            }
        },
        "trained_image_ensemble": True,
    }


def reset_for_tests() -> None:
    global _MODELS
    _MODELS = None
