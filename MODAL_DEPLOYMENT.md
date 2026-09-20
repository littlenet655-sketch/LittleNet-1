# LittleNet on Modal

_Last updated: 2026-09-20_

## Architecture

LittleNet uses a split deployment so the Flask/Jinja social application stays lightweight while heavy safety/face inference runs on Modal GPU infrastructure.

- **Web:** `modal_web.py` (Flask/Jinja)
- **Heavy AI:** `modal_ai.py` on a T4 GPU
- **Database:** external PostgreSQL (for example Neon)
- **Private media:** Cloudflare R2
- **Android:** React Native + Expo client using the verified API URL; media and face flows stay protected by the backend and Modal AI

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

These values are intentionally not committed. The deployment workflow validates them at runtime and fails before spending GPU credits when they are absent or invalid.

## Modal secrets

Create the AI secret with the same shared secret used by the web service:

```bash
modal secret create littlenet-ai-secrets \
  AI_SHARED_SECRET="<long-random-shared-secret>"
```

The web secret must contain the real runtime configuration. The Modal definition requires these core keys:

```text
DATABASE_URL
SECRET_KEY
AI_SERVICE_URL
AI_SHARED_SECRET
```

The live release preflight additionally requires a real public `BASE_URL`, working private R2 storage, and working Resend credentials.

Put `BASE_URL` in `littlenet-web-secrets`. Put private media credentials in the separately mounted `littlenet-r2` secret:

```text
R2_ACCOUNT_ID
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
R2_BUCKET
R2_SIGNED_URL_TTL
```

Optional adaptive video settings also belong in `littlenet-r2` because that secret is mounted only on backend functions:

```text
CLOUDFLARE_STREAM_ENABLED=1
CLOUDFLARE_STREAM_ACCOUNT_ID
CLOUDFLARE_STREAM_API_TOKEN
CLOUDFLARE_STREAM_SUBDOMAIN
CLOUDFLARE_STREAM_API_TIMEOUT_SECONDS
CLOUDFLARE_STREAM_SIGNING_KEY_ID
CLOUDFLARE_STREAM_SIGNING_PRIVATE_KEY_B64
```

Leave `CLOUDFLARE_STREAM_ENABLED` unset/0 until real Stream credentials are configured. LittleNet then stays on its private sanitized R2 MP4 path.

For mail, configure the verified Resend production sender in the `littlenet-email` Modal secret. `modal_web.py` attaches this secret to the live web function; updating only a local Replit secret or only `littlenet-web-secrets` does not refresh the running deployment.

The parent OTP path has a fixed sender contract independent of deployment
defaults: every parent verification email is sent as
`LittleNet <no-reply@littlenet.in>`. `RESEND_FROM_EMAIL` and
`RESEND_FROM_NAME` cannot override that identity for OTP delivery. The
LittleNet domain must remain verified in Resend; an unverified or sandbox
sender is not an acceptable fallback.

```text
RESEND_API_KEY
RESEND_WEBHOOK_SECRET
RESEND_FROM_EMAIL
RESEND_FROM_NAME
```

The sender must be a domain-verified LittleNet address. Configure a Resend webhook for `https://<public-littlenet-web-url>/webhooks/resend` and subscribe to delivery, bounce, failed, suppressed and complaint events. `RESEND_WEBHOOK_SECRET` must be the signing secret for that webhook. LittleNet deliberately does not fall back to a sandbox sender, SMTP, or demo delivery because parent OTP success must prove real inbox delivery.


A complete split-secret example is:

```bash
modal secret create littlenet-web-secrets --force \
  DATABASE_URL="postgresql://..." \
  SECRET_KEY="<long-random-flask-secret>" \
  AI_SERVICE_URL="https://<modal-ai-web-url>" \
  AI_SHARED_SECRET="<same-shared-secret>" \
  BASE_URL="https://<public-littlenet-web-url>"
```

```bash
modal secret create littlenet-r2 --force \
  R2_ACCOUNT_ID="<cloudflare-account-id>" \
  R2_ACCESS_KEY_ID="<r2-access-key>" \
  R2_SECRET_ACCESS_KEY="<r2-secret-key>" \
  R2_BUCKET="<private-bucket-name>" \
  R2_SIGNED_URL_TTL="600"
```

```bash
modal secret create littlenet-email --force \
  RESEND_API_KEY="<resend-api-key>" \
  RESEND_WEBHOOK_SECRET="<resend-webhook-signing-secret>" \
  RESEND_FROM_EMAIL="no-reply@littlenet.in" \
  RESEND_FROM_NAME="LittleNet"
```

The release preflight validates the database/schema, quiz bank, AI configuration, Presidio PII detection, MediaPipe liveness assets, public `BASE_URL`, Resend readiness, R2 bucket access and the configured video-delivery provider. If Stream is disabled, the private R2 fallback is the accepted provider; if Stream is enabled, its API configuration must pass.

## Recommended release path

Use GitHub Actions **Deploy & Validate LittleNet Live** instead of manually performing isolated commands:

```text
Modal auth validation
→ AI deploy
→ web deploy
→ PostgreSQL init/migrations
→ quiz seed
→ DB/AI/Presidio/liveness/mail/R2/BASE_URL preflight
→ T4 model warm/validation
→ public health/readiness checks
→ Playwright browser smoke
→ live-URL Android APK build
```

The inexpensive runtime/configuration gates deliberately run before the T4 model warm step. This prevents GPU credits being spent when the release would later fail because of missing database, mail, R2, or public URL configuration.

The release fails immediately if any dependency is missing or degraded. A final APK is not produced from a degraded deployment.

## Equivalent manual commands for diagnosis

```bash
python -m pip install -r requirements-modal.txt
modal token info
modal deploy modal_ai.py
modal deploy modal_web.py
modal run modal_web.py --init-db
modal run modal_web.py --seed
modal run modal_web.py --preflight
modal run modal_ai.py
```

Then require `GET /healthz` = HTTP 200/ok and `GET /readyz` = HTTP 200/ready.

## Cost behavior

The heavy AI deployment scales to zero when idle and uses a finite scaledown window so college/demo usage does not unnecessarily burn GPU credits. Expect a cold start after idle periods; warm the deployment before a judged demo.

## Release artifact rule

The source repository does not contain the canonical final APK. The only final APK is the `LittleNet-live-verified-apk` Actions artifact produced after the complete live gate passes.
