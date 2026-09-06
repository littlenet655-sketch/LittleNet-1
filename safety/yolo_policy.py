"""YOLO dangerous-object classification policy for LittleNet.

YOLO model confidence is treated as evidence, not as a direct child-safety
probability. Dangerous detections in the medium-confidence band are therefore
routed to Parent Review instead of being silently allowed.
"""
from __future__ import annotations

import os
import re
from typing import Iterable


def _threshold(name: str, default: float) -> float:
    try:
        value = float(os.getenv(name, str(default)))
    except ValueError:
        value = default
    return max(0.0, min(value, 1.0))


YOLO_REVIEW_THRESHOLD = _threshold('LITTLENET_YOLO_REVIEW_THRESHOLD', 0.20)
YOLO_BLOCK_THRESHOLD = _threshold('LITTLENET_YOLO_BLOCK_THRESHOLD', 0.45)
if YOLO_BLOCK_THRESHOLD < YOLO_REVIEW_THRESHOLD:
    YOLO_BLOCK_THRESHOLD = YOLO_REVIEW_THRESHOLD

# Open Images + common COCO/Ultralytics vocabulary variants. Keep terms narrow
# enough to avoid matching harmless classes such as "water gun toy" by accident;
# callers can still add deployment-specific labels through the env variable.
_DANGEROUS_TERMS = {
    'firearm': {
        'gun', 'handgun', 'pistol', 'revolver', 'rifle', 'shotgun', 'firearm',
        'machine gun', 'submachine gun', 'assault rifle', 'sniper rifle',
    },
    'blade': {
        'knife', 'kitchen knife', 'dagger', 'sword', 'machete', 'axe', 'hatchet',
        'cleaver', 'switchblade',
    },
    'explosive': {
        'bomb', 'grenade', 'explosive', 'land mine', 'landmine', 'dynamite',
        'rocket launcher',
    },
    'other_weapon': {
        'crossbow', 'bow and arrow', 'chainsaw', 'weapon',
    },
}


def _extra_terms() -> set[str]:
    raw = os.getenv('LITTLENET_DANGEROUS_OBJECTS', '')
    return {normalize_label(x) for x in raw.split(',') if normalize_label(x)}


def normalize_label(label: str) -> str:
    value = str(label or '').strip().lower().replace('_', ' ').replace('-', ' ')
    return re.sub(r'\s+', ' ', value)


def classify_label(label: str) -> str | None:
    norm = normalize_label(label)
    if not norm:
        return None
    for family, terms in _DANGEROUS_TERMS.items():
        if norm in terms:
            return family
    if norm in _extra_terms():
        return 'custom_dangerous'
    return None


def classify_detections(detections: Iterable[dict] | None) -> dict:
    dangerous = []
    max_score = 0.0
    for row in detections or []:
        label = normalize_label(row.get('label', ''))
        family = classify_label(label)
        if not family:
            continue
        try:
            confidence = float(row.get('confidence', 0) or 0)
        except (TypeError, ValueError):
            confidence = 0.0
        confidence = max(0.0, min(confidence, 1.0))
        max_score = max(max_score, confidence)
        dangerous.append({
            'label': label,
            'family': family,
            'confidence': round(confidence, 4),
        })

    dangerous.sort(key=lambda x: x['confidence'], reverse=True)
    return {
        'dangerous': dangerous[:25],
        'score': max_score,
        'block': bool(dangerous and max_score >= YOLO_BLOCK_THRESHOLD),
        'review': bool(dangerous and YOLO_REVIEW_THRESHOLD <= max_score < YOLO_BLOCK_THRESHOLD),
        'review_threshold': YOLO_REVIEW_THRESHOLD,
        'block_threshold': YOLO_BLOCK_THRESHOLD,
    }


def _walk_model_signals(value):
    if isinstance(value, dict):
        yolo = value.get('yolo')
        if isinstance(yolo, dict):
            yield from yolo.get('detections') or []
        for child in value.values():
            yield from _walk_model_signals(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_model_signals(child)


def classify_signals(signals: dict | None) -> dict:
    """Classify YOLO detections from image or sampled-video model diagnostics."""
    model_signals = (signals or {}).get('model_signals') or {}
    return classify_detections(list(_walk_model_signals(model_signals)))


def dangerous_label_coverage(model_names) -> list[str]:
    """Return dangerous labels actually exposed by a loaded YOLO checkpoint."""
    if isinstance(model_names, dict):
        names = model_names.values()
    else:
        names = model_names or []
    matched = sorted({normalize_label(name) for name in names if classify_label(name)})
    return matched
