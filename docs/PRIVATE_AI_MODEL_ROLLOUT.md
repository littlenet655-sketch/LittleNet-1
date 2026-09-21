# LittleNet Private AI Model Rollout

This runbook keeps the current working moderation paths untouched until private
checkpoints have been staged and verified.

## Private Modal volume

Existing volume: `littlenet-model-cache`

Image checkpoints:

- `/cache/models/littlenet_core_safety_v2.pth`
- `/cache/models/littlenet_weapons_violence_v3.pth`

Text bundle:

- `/cache/models/littlenet_text_safety/config.json`
- `/cache/models/littlenet_text_safety/model.safetensors` or `pytorch_model.bin`
- normal Hugging Face tokenizer files
- `/cache/models/littlenet_text_safety/littlenet_metadata.json`

Never commit private trained checkpoints to Git.

## Text metadata contract

```json
{
  "format": "huggingface_sequence_classification",
  "release": "text-v2-epoch3",
  "labels": ["label_a", "label_b"],
  "thresholds": {
    "label_a": 0.50,
    "label_b": 0.50
  },
  "activation": "sigmoid",
  "max_length": 256,
  "signal_map": {
    "optional_label_name": "toxicity"
  }
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
