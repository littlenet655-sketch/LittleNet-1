# LittleNet on Modal

_Last updated: 2026-09-07_

## Architecture

LittleNet uses a split deployment so the Flask/Jinja social application stays lightweight while heavy safety/face inference runs on Modal GPU infrastructure.

- **Web:** `modal_web.py` (Flask/Jinja)
- **Heavy AI:** `modal_ai.py` on a T4 GPU
- **Database:** external PostgreSQL (for example Neon)
- **Private media:** Cloudflare R2
- **Android:** WebView app pointing only at the verified public web URL; the web app calls protected Modal AI internally

Standalone speech/audio moderation is intentionally outside the locked current scope. Uploaded child videos are sanitized to remove audio before persistence. Old instructions mentioning active Whisper/Faster-Whisper warm-up are obsolete.

## AI service

`modal_ai.py` exposes protected endpoints used by `safety/remote_client.py`, including health, TEXT/IMAGE/VIDEO moderation, face embedding/verification/adult verification and safe-candidate semantic ranking.

The warm gate validates the current locked model/dependency stack: Detoxify multilingual sexual-explicit output, NudeNet, CLIP, Falconsai NSFW, OpenImages-capable YOLO dangerous-object coverage, DeepFace/Facenet512 and PySceneDetect.

## Required GitHub Actions credentials

The connected release workflow authenticates to Modal using GitHub repository secrets:

```text
MODAL_TOKEN_ID
MODAL_TOKEN_SECRET
```

These are intentionally not committed. The 2026-09-07 live-release run proved they are currently missing from GitHub Actions. Add them in the repository Actions secrets, then rerun **Deploy & Validate LittleNet Live**.

## Modal secrets

Create the AI secret with the same shared secret used by the web service:

```bash
modal secret create littlenet-ai-secrets \
  AI_SHARED_SECRET="<long-random-shared-secret>"
```

The web secret must contain the real runtime configuration. At minimum the Modal definition requires:

```bash
modal secret create littlenet-web-secrets \
  DATABASE_URL="postgresql://..." \
  SECRET_KEY="<long-random-flask-secret>" \
  AI_SERVICE_URL="https://<modal-ai-web-url>" \
  AI_SHARED_SECRET="<same-shared-secret>" \
  BASE_URL="https://<public-littlenet-web-url>"
```

For a full live-ready release, also configure the SMTP/mail and private R2 variables expected by the application in the same runtime secret/environment. The release preflight verifies them instead of silently falling back to demo behavior.

## Recommended release path

Use GitHub Actions **Deploy & Validate LittleNet Live** instead of manually performing isolated commands:

```text
Modal auth validation
→ AI deploy
→ model warm/validation
→ web deploy
→ PostgreSQL init/migrations
→ quiz seed
→ DB/AI/Presidio/liveness/mail/R2/BASE_URL preflight
→ public health/readiness checks
→ Playwright browser smoke
→ live-URL Android APK build
```

The release fails immediately if any dependency is missing or degraded. A final APK is not produced from a degraded deployment.

## Equivalent manual commands for diagnosis

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

Then require `GET /healthz` = HTTP 200/ok and `GET /readyz` = HTTP 200/ready.

## Cost behavior

The heavy AI deployment scales to zero when idle and uses a finite scaledown window so college/demo usage does not unnecessarily burn GPU credits. Expect a cold start after idle periods; warm the deployment before a judged demo.

## Release artifact rule

The source repository does not contain the canonical final APK. The only final APK is the `LittleNet-live-verified-apk` Actions artifact produced after the complete live gate passes.
