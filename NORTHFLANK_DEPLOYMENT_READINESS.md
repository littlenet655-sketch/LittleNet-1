# LittleNet — Northflank Deployment Readiness Checklist (Phase 2.5)

**Date:** 2026-09-10
**Target:** Northflank FREE DEV environment — US Central / Council Bluffs
**Project:** LittleNet
**PostgreSQL addon:** `littlenet-db-dev`
**API service:** NOT YET DEPLOYED (readiness check only)
**Instruction:** DO NOT DEPLOY until this checklist passes

---

## Phase 2.5 Hardening — Completed Before Deploy

| Item | Status | Evidence |
|------|--------|----------|
| mock-PUT production guard | DONE | `mobile/api.py` returns 404 in HTTPS or without `ENABLE_MOCK_PUT=1` |
| Upload session expiry enforced | DONE | `upload_session_expired` returned on expired sessions |
| Cross-user session theft blocked | DONE | 403 `forbidden_upload_owner_mismatch` on ownership mismatch |
| Extension/MIME whitelist | DONE | Only jpg/jpeg/png/webp/mp4/mov/webm/mkv allowed |
| File size limits per media type | DONE | IMAGE <= 20 MB, STORY <= 50 MB |
| Idempotent /complete | DONE | Repeated calls return same `post_id` + `idempotent=true` |
| Quarantine isolation | DONE | PROCESSING/PENDING posts never appear in child feed |
| All Phase 2.5 unit tests | DONE | `tests/test_phase25_production_hardening.py` |
| Flutter hashtag validation | DONE | `create_post_screen.dart` client-side + server-side mirror |
| Flutter UploadManager | DONE | `lib/core/upload/upload_manager.dart` |
| Flutter UploadProgressBanner | DONE | `lib/core/upload/upload_progress_banner.dart` |

---

## Required Environment Variables for Northflank

Set these as environment variables in the Northflank service (not committed to source):

### Mandatory (service will fail to start without these)

  SECRET_KEY=<at least 32 random chars>
  DATABASE_URL=<northflank postgresql connection string from littlenet-db-dev addon>
  BASE_URL=https://<your-northflank-service-url>
  COOKIE_SECURE=1

### Upload Security (Phase 2.5)

  # DO NOT set ENABLE_MOCK_PUT in production - mock-PUT must stay disabled
  # Default is disabled (env var absent or 0)

### AI Moderation Service

  AI_SERVICE_URL=https://<your-ai-service-url>
  AI_SHARED_SECRET=<long random secret>

### Cloudflare R2 Media Storage

  R2_ACCOUNT_ID=<from Cloudflare dashboard>
  R2_ACCESS_KEY_ID=<R2 API token key>
  R2_SECRET_ACCESS_KEY=<R2 API token secret>
  R2_BUCKET=littlenet-media
  R2_SIGNED_URL_TTL=300

### SMTP / Mail (guardian OTP)

  SMTP_HOST=smtp.gmail.com
  SMTP_PORT=587
  SMTP_USER=<gmail address>
  SMTP_PASSWORD=<app password>
  SMTP_USE_TLS=true
  MAIL_EMAIL=<from email>

### K2 Horizon AI Gateway (optional but recommended)

  K2_HORIZON_ENABLED=true
  K2_HORIZON_BASE_URL=https://api.ifm.ai/v1
  K2_HORIZON_API_KEY=<IFM key>
  K2_HORIZON_MODEL=IFM/K2-Horizon-375B-A23B

### Timezone

  APP_TIMEZONE=Asia/Kolkata

---

## Docker Build Configuration for Northflank

- **Dockerfile:** `Dockerfile.web`
- **Port:** `8080` (Northflank maps external -> 8080)
- **Start command:** `/app/docker-entrypoint.sh` (do NOT override)
- **Health check path:** `/healthz`
- **Health check timeout:** 180 seconds (model warm-up)

### What docker-entrypoint.sh does automatically

1. Creates `/data/uploads`, `/data/models`, `/data/cache` persistent directories
2. Symlinks `/app/uploads` -> `/data/uploads`
3. Runs `python tools/init_db.py` (idempotent schema bootstrap)
4. Runs `dbmate up` (applies any pending migrations)
5. Starts gunicorn: `workers=1, threads=4, timeout=240`

---

## Health Endpoints

| Endpoint | Expected Response | Checks |
|----------|-------------------|--------|
| `GET /healthz` | `200 OK` with `{"status":"ok"}` | App alive |
| `GET /readyz` | `200 OK` with `{"status":"ready"}` | DB + AI + R2 reachability |

Deploy is NOT healthy until `/readyz` returns `ready`. Check logs if it stays `not_ready`.

---

## Pre-Deploy Validation Checklist

Run these locally before triggering a Northflank deploy:

### 1. Python Unit Tests

  python -m pytest tests/ -v --tb=short -q
  python -m pytest tests/test_phase2_upload_and_tags.py tests/test_phase25_production_hardening.py -v

Expected: All pass (currently ~370+ tests)

### 2. Contract Checks

  python -m pytest tests/test_contracts.py -v --tb=short

### 3. Final Hardening Suite

  python -m pytest tests/test_final_hardening.py tests/test_k2_ai_safety.py -v --tb=short

### 4. Git Status - No Uncommitted Changes

  git status
  git diff --stat

---

## Known Blockers

| Blocker | Status | Resolution |
|---------|--------|------------|
| ENABLE_MOCK_PUT must NOT be set in prod | FIXED | Production guard in code |
| R2 credentials not configured | REQUIRED | Set R2 env vars in Northflank |
| AI service URL | REQUIRED | Deploy AI service first, set AI_SERVICE_URL |
| SMTP credentials | REQUIRED | Set SMTP env vars |
| Northflank persistent storage | CHECK | /data must be a persistent volume or ephemeral uploads are lost on restart |

---

## Deployment Order

When ready to deploy (not now - readiness only):

1. Configure all env vars in Northflank -> littlenet-web service
2. Ensure littlenet-db-dev addon is RUNNING
3. Connect GitHub repo (littlenet655-sketch/LittleNet-1) to service
4. Trigger first build from main branch
5. Wait for /healthz -> 200 (allow 3-5 min cold start)
6. Verify /readyz -> {"status": "ready"}
7. Run live smoke test: register parent, create child, post image
8. Confirm mock-PUT returns 404 from production URL

---

## Post-Deploy Security Verification

After first successful deploy, verify these with curl against the live URL:

  # 1. Confirm mock-PUT is DISABLED in production (MUST return 404)
  curl -X PUT https://<northflank-url>/api/mobile/v2/uploads/mock-put/test123 \
    -H "Content-Type: image/jpeg" -d "data"
  # Expected: {"error": "not_found"} HTTP 404

  # 2. Confirm /healthz
  curl https://<northflank-url>/healthz
  # Expected: {"status": "ok"}

  # 3. Confirm /readyz
  curl https://<northflank-url>/readyz
  # Expected: {"status": "ready"}

  # 4. Confirm upload session requires auth
  curl -X POST https://<northflank-url>/api/mobile/v2/uploads/session \
    -H "Content-Type: application/json" \
    -d '{"kind":"post","media_type":"IMAGE","size_bytes":1024,"extension":"jpg"}'
  # Expected: 401 Unauthorized

---

Status: READY FOR NORTHFLANK DEPLOYMENT (after env vars are configured)
