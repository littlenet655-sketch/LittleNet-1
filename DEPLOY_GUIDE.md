# LittleNet Deployment Guide — Current Release Path

_Last updated: 2026-09-07_

## Use the connected release workflow

The canonical deployment is `.github/workflows/deploy-modal.yml` (**Deploy & Validate LittleNet Live**). It replaces the older disconnected Railway/Modal/APK instructions.

### 1. GitHub Actions → Modal authentication

Add repository Actions secrets:

```text
MODAL_TOKEN_ID
MODAL_TOKEN_SECRET
```

The latest live run proved these are currently missing. Do not put them in source files.

### 2. Configure Modal runtime secrets

`littlenet-ai-secrets` must contain the AI shared secret. `littlenet-web-secrets` must contain the real PostgreSQL, Flask, AI-service, public-base-URL, mail and private-R2 configuration required by the application.

### 3. Run Deploy & Validate LittleNet Live

The workflow performs, in order:

```text
AI deploy + warm
→ web deploy
→ PostgreSQL bootstrap/migrations
→ compulsory quiz seed
→ DB/AI/Presidio/MediaPipe/mail/R2/BASE_URL preflight
→ public /healthz + strict /readyz
→ Playwright browser smoke
→ live-backed Android APK build
```

If any stage fails, fix that exact dependency and rerun. Do not skip forward to APK generation.

## Current AI scope

The locked release moderates TEXT/IMAGE/VIDEO. It uses Detoxify/text rules, NudeNet, Falconsai NSFW, CLIP, YOLO dangerous-object policy, scene-aware video-frame selection and DeepFace/face safety. Standalone audio/voice moderation is disabled; child videos are stripped of audio before persistence.

## Final APK

Do not use a repository-root APK. After the live workflow is green, download the `LittleNet-live-verified-apk` Actions artifact. Install it on a real Android device and test:

1. Parent registration/OTP/camera verification
2. Child account creation and confirmation
3. child face enrollment/login
4. safe and blocked text/image/video uploads
5. private media loading
6. Parent Review and controls
7. camera/file permissions in the Android WebView

## Manual diagnostic commands

When diagnosing Modal directly:

```bash
python -m pip install -r requirements-modal.txt
modal token info
modal deploy modal_ai.py
modal run modal_ai.py
modal deploy modal_web.py
modal run modal_web.py --init-db
modal run modal_web.py --seed
modal run modal_web.py --preflight
```

A judged demo should be warmed shortly before presentation to avoid GPU cold-start latency, then allowed to scale down afterward.
