# Wave 2 verification scope

This branch is intentionally limited to lightweight safety/privacy hardening:

- real browser-side MediaPipe Face Landmarker blink detection for Parent liveness;
- integrity-verified, self-hosted MediaPipe Tasks Vision 1.0.1 browser runtime and face-landmarker model;
- replay-resistant two-parent friendship activation at the PostgreSQL trigger layer;
- canonical post/story visibility checks before local or R2 media delivery;
- active-friend requirement for direct message media after friendship changes;
- discovery authorization for child profile-picture delivery;
- Messages Notes limited to ACTIVE two-parent-approved friends, excluding blocked/muted peers;
- CI now executes pytest plus a real pinned MediaPipe upstream asset verification.

No heavyweight Hugging Face candidate is enabled on the default request path in this wave.
