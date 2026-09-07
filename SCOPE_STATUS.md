# LittleNet Scope Status

`python tools/scope_check.py` maps the corrected project scope and locked final additions to source-level evidence.

Run the command for the current count; do not rely on an old hard-coded `41/41` number after new hardening checks are added.

Current locked scope includes Kids/Parent/Admin modes; Feed/posts/Clips/Reels/Stories/chat; two-parent-approved social interaction; non-global Discover; text/PII safety; NSFW/YOLO/CLIP image/video safety; Parent Review; parent-first account flow; screen time/quiet hours; alerts; behavior/quiz metrics; age targeting/personalization; multilingual UI; learning/quiz gates; Face Login/liveness; private media; PostgreSQL audit data; Android source; and Modal deployment gates.

Standalone audio/voice moderation is **not** part of the active locked runtime. Video audio is stripped before persistence.

This is a source-scope check, not proof that external cloud credentials, production services, cameras or the final live APK have passed.
