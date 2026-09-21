# LittleNet Private AI Model Rollout

This runbook keeps the current working moderation paths untouched until private
checkpoints have been staged and verified.

## Private Modal volume

Existing volume: `littlenet-model-cache`

Image checkpoints:

- `/cache/models/littlenet_core_safety_v2.pth`
- `/cache/models/littlenet_weapons_violence_v3.pth`

Text bundle — current Final V2 artifact:

- `/cache/models/littlenet_text_safety/littlenet_text_model.pt`
- `/cache/models/littlenet_text_safety/metadata.json`
- `/cache/models/littlenet_text_safety/dual_threshold_policy.json` when present
- `/cache/models/littlenet_text_safety/thresholds_validation.json` when present
- tokenizer files in `/cache/models/littlenet_text_safety/`
- saved encoder/config in `/cache/models/littlenet_text_safety/encoder/`

The adapter matches the trained V2 architecture: multilingual DistilBERT AutoModel,
first-token embedding, Dropout(0.20), Linear(hidden_size, 13), max length 128.

Frozen V2 label order:

`sexual, grooming, bullying, hate, violence, self_harm, drugs, alcohol, smoking, gambling, profanity, pii_request, contact_request`

A standard Hugging Face sequence-classification bundle remains supported for future
model versions.

Never commit private trained checkpoints to Git.

## Optional metadata contract for future HF bundles

```json
{
  "format": "huggingface_sequence_classification",
  "release": "text-future-release",
  "labels": ["label_a", "label_b"],
  "review_thresholds": {"label_a": 0.50, "label_b": 0.50},
  "block_thresholds": {"label_a": 0.80, "label_b": 0.80},
  "activation": "sigmoid",
  "max_length": 256,
  "signal_map": {"optional_label_name": "toxicity"}
}
```

Supported signal-map values are `adult`, `sexual`, `violence`, `weapon`,
`toxicity`, `general`, and `ignore`. Safe/clean/benign/neutral labels are
ignored automatically unless metadata explicitly maps them.

## Safe sequence

1. Keep `LITTLENET_TRAINED_TEXT_MODE=off`.
2. Upload private image and text artifacts to the existing Modal model volume.
3. Run:
   - `modal run modal_ai.py --trained-image-preflight-only`
   - `modal run modal_ai.py --trained-text-preflight-only`
4. Keep production decisions unchanged and switch text to `shadow`.
5. Compare shadow evidence against the frozen benchmark and current decisions.
6. Set the same `LITTLENET_TRAINED_TEXT_RELEASE` in AI and web deployment config.
7. Switch text to `enforce` only after shadow verification.
8. Run the full parent -> child -> upload -> moderation -> second-child E2E.
9. If anything regresses, return text mode to `off`; existing rules + Detoxify
   immediately remain the authority.

## Cache safety

While mode is `off` or `shadow`, the existing moderation-cache version is
unchanged. In `enforce` mode, the trained-text release is appended to the cache
key so legacy text evidence cannot be reused under a new model.

## Image behavior

The trained image ensemble is used only when both V2 and V3 checkpoints exist
and load. Missing/invalid private image checkpoints leave the existing
NudeNet/FalconsAI/YOLO/CLIP fallback available.

## Release workflow

The manual Modal workflow exposes `verify_private_trained_models`. When enabled,
it runs both private-model preflights but does not activate trained text.
