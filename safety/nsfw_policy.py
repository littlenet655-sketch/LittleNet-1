"""Per-model NSFW policy for LittleNet image/video moderation.

Raw scores from NudeNet, FalconsAI and CLIP are not directly comparable. This
module keeps model-specific review/block thresholds and converts their evidence
into a consistent child-safety action. Raw scores remain available in
``model_signals`` for later benchmark calibration.
"""
from __future__ import annotations

import os


def _env_float(name: str, default: float) -> float:
    try:
        value = float(os.getenv(name, str(default)))
    except ValueError:
        value = default
    return max(0.0, min(1.0, value))


_DEFAULTS = {
    'nudenet': (0.20, 0.45),
    'falconsai': (0.40, 0.70),
    'clip': (0.40, 0.65),
    'opennsfw2': (0.35, 0.70),
    'extra_nsfw': (0.40, 0.75),
}


def thresholds(model: str) -> tuple[float, float]:
    key = model.upper().replace('-', '_')
    review_default, block_default = _DEFAULTS[model]
    review = _env_float(f'LITTLENET_{key}_REVIEW_THRESHOLD', review_default)
    block = _env_float(f'LITTLENET_{key}_BLOCK_THRESHOLD', block_default)
    return review, max(review, block)


def _walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _score_from_node(model: str, node: dict):
    if model == 'clip':
        clip = node.get('clip')
        if isinstance(clip, dict):
            return max(float(clip.get('adult', 0) or 0), float(clip.get('sexual', 0) or 0))
        return None
    value = node.get(model)
    if isinstance(value, (int, float)):
        return float(value)
    return None


def classify_signals(signals: dict | None) -> dict:
    model_signals = (signals or {}).get('model_signals') or {}
    evidence = []
    for node in _walk(model_signals):
        for model in _DEFAULTS:
            score = _score_from_node(model, node)
            if score is None:
                continue
            review_t, block_t = thresholds(model)
            evidence.append({
                'model': model,
                'score': max(0.0, min(1.0, score)),
                'review_threshold': review_t,
                'block_threshold': block_t,
            })

    block_rows = [e for e in evidence if e['score'] >= e['block_threshold']]
    review_rows = [e for e in evidence if e['review_threshold'] <= e['score'] < e['block_threshold']]
    top = max(evidence, key=lambda e: e['score'], default=None)
    return {
        'has_evidence': bool(evidence),
        'block': bool(block_rows),
        'review': bool(review_rows) and not bool(block_rows),
        'top': top,
        'evidence': sorted(evidence, key=lambda e: e['score'], reverse=True)[:25],
    }
