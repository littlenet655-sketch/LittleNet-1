# LittleNet on Modal

## Recommended architecture

For the college-project build, the most practical free/low-cost architecture is:

- **Web + social + Parent/Admin + PostgreSQL client:** Railway/another lightweight Python host.
- **Heavy AI:** Modal Starter using the included `modal_ai.py`.
- **Database:** PostgreSQL on Railway/Neon/Supabase; do not use a Modal Volume as a relational database.
- **Android APK:** points only at the web service. The web service calls Modal AI internally.

This avoids forcing Torch + Transformers + TensorFlow + Whisper + DeepFace into Railway Free's small RAM limit.

## Why Modal fits the AI part

`modal_ai.py` runs the existing LittleNet AI HTTP API on a T4 GPU and keeps model caches in a Modal Volume. It exposes the endpoints used by `safety/remote_client.py` for moderation, face verification and CLIP-semantic For You ranking, so no UI/route rewrite is required.

The AI service exposes:

- `GET /healthz`
- `POST /ai/moderate`
- `POST /ai/face/embedding`
- `POST /ai/face/verify`
- `POST /ai/rank` for semantic ranking of an already-safe candidate set

## 1. Install and authenticate Modal

```bash
python -m pip install -r requirements-modal.txt
modal setup
```

## 2. Create the AI shared secret

Generate a long random value, then create the Modal secret:

```bash
modal secret create littlenet-ai-secrets AI_SHARED_SECRET="replace-with-a-long-random-secret"
```

Use the **same value** as `AI_SHARED_SECRET` on the LittleNet web service.

## 3. Warm/download models

```bash
modal run modal_ai.py
```

This invokes the `warm_models` function on a T4 and reports readiness for Detoxify, Faster-Whisper, NudeNet, CLIP, Falconsai NSFW, YOLO and DeepFace/Facenet512.

## 4. Deploy

```bash
modal deploy modal_ai.py
```

Modal returns an HTTPS Web Function URL. Set that on the web service:

```env
AI_SERVICE_URL=https://<your-modal-web-function-url>
AI_SHARED_SECRET=<same-secret>
AI_REQUEST_TIMEOUT=180
```

Then check LittleNet's `/readyz` endpoint.

## 5. Cost behavior

The deployment is intentionally configured with `min_containers=0` and a 300-second scaledown window. That means the GPU scales to zero when unused, preserving Starter credits. The first AI request after an idle period can have a cold start; for a college demo, warm it a few minutes before presenting.

## Optional: host the Flask web UI itself on Modal

This repository now includes `modal_web.py`. It serves the complete Flask/Jinja app as a Modal WSGI Web Function and mounts `littlenet-uploads` as a persistent Volume. PostgreSQL still stays external.

Create the web secret after the AI URL is known:

```bash
modal secret create littlenet-web-secrets \
  DATABASE_URL="postgresql://..." \
  SECRET_KEY="replace-with-long-random-value" \
  AI_SERVICE_URL="https://<modal-ai-url>" \
  AI_SHARED_SECRET="<same-ai-secret>" \
  BASE_URL="https://<modal-web-url>"
```

Then:

```bash
modal deploy modal_web.py
modal run modal_web.py::init_database
modal run modal_web.py::web_preflight
```

Because `BASE_URL` is used in parent-approval email links, set it to the generated Modal web URL after the first deployment and redeploy/update the secret if necessary.

The web function is intentionally capped at one container for this college build. This makes persistent upload writes predictable with Modal Volume semantics. If LittleNet were scaled to many simultaneous users, uploads should move to object storage rather than a shared filesystem.
