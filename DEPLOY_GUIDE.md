# LittleNet — deploy to live, then build the APK

Follow this in order. Each phase blocks the next — don't skip ahead.

Two safety decisions are already built into this copy of the repo:
- Face login always has a working "Use password login instead" link, and
  any face-service exception/timeout falls back to the password form
  instead of a dead end (see `auth/routes.py` `/face-login/` and
  `auth/templates/face_login.html`).
- `modal_ai.py` ships with `min_containers=0` (cost-safe idle). Use
  `tools/demo_warm.sh` before a demo and `tools/demo_cooldown.sh` after —
  see Phase 6.

---

## Phase 1 — Database

Provision Postgres on Railway, Neon, or Supabase (not a Modal Volume).

```bash
psql "$DATABASE_URL" -f database/schema.sql
psql "$DATABASE_URL" -f database/upgrade.sql
```

Keep the connection string — it's `DATABASE_URL` in Phase 2.

## Phase 2 — Web service (Railway)

Deploy `Dockerfile.web`. This installs `requirements-core.txt` +
`requirements-text.txt` only — the heavy vision/audio/face stack stays
out of this service on purpose (see the comment at the top of
`requirements-text.txt`).

Set these environment variables on the Railway service:

```
SECRET_KEY=<generate a long random value>
DATABASE_URL=<from Phase 1>
BASE_URL=https://<your-railway-domain>
COOKIE_SECURE=1
MAIL_EMAIL=<your sending address>
MAIL_PASSWORD=<app password>
```

Deploy, then confirm `https://<your-railway-domain>/healthz` returns OK.
This URL is what the APK will point at in Phase 5 — don't lose it.

## Phase 3 — Modal AI service

```bash
python -m pip install -r requirements-modal.txt
modal setup
modal secret create littlenet-ai-secrets AI_SHARED_SECRET="<another long random value>"
modal run modal_ai.py          # warms Detoxify, Whisper, NudeNet, CLIP,
                                # Falconsai, YOLO, and DeepFace/Facenet512
modal deploy modal_ai.py
```

Modal returns an HTTPS Web Function URL. Add it to the Railway web
service's environment (redeploy after adding):

```
AI_SERVICE_URL=https://<your-modal-url>
AI_SHARED_SECRET=<same value as the Modal secret above>
```

## Phase 4 — Verify against the live services, don't assume

```bash
python tools/preflight.py
python tools/readiness.py
python -m pytest tests/ -v
```

This is the first point where the test suite means anything — it needs
the live DB from Phase 1. Expect some failures on first run against real
infrastructure; fix them here, not on submission day.

## Phase 5 — Build the APK

Only after Phase 2's URL is stable and tested.

```bash
python tools/set_backend_url.py https://<your-railway-domain>
```

Then trigger `.github/workflows/build-apk.yml` (GitHub Actions →
"Build LittleNet APK" → Run workflow), passing the same backend URL.
Download the signed APK from the workflow's artifacts.

Install it on a real Android device and test, in this order:
1. Password login (must always work — this is your guaranteed path)
2. Upload flow: image, video, text, audio moderation
3. Camera/mic permission prompts
4. Face enroll + face login, including the "Use password login instead"
   fallback link when you deliberately give it a bad photo

## Phase 6 — Before the actual demo/viva

Run this 15-20 minutes before you present, not the night before:

```bash
./tools/demo_warm.sh
```

This pins the Modal container warm so the first upload doesn't eat a
10-30s cold start in front of a professor. Right after you're done:

```bash
./tools/demo_cooldown.sh
```

A warm GPU container costs money for every minute it's up — don't leave
it running.

## Phase 7 — Content QA

Upload real safe and unsafe samples (image/video/audio/text) against the
live pipeline and confirm the moderation decisions match what you'd
expect before submission. `tools/model_warmup.py` and `tools/scope_check.py`
help spot gaps, but they don't replace actually looking at the results.

---

## If something breaks close to the deadline

- **Modal/network flaky, not enough time to debug:** run the AI models
  directly inside the Flask service instead of Modal (heavier per-request,
  but one less network hop). Revert to Modal after submission if you want.
- **Face login unreliable:** leave it in place — it already falls back to
  password login on any failure — but don't lead the demo with it. Show
  the app working end to end on password login first, then show face
  login as a bonus if it's behaving.
- **Record a backup demo video once everything works end to end.**
  Insurance against a bad network day, not a replacement for the live app.
