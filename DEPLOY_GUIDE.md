# LittleNet Deployment Guide

> **Superseded.** The single authoritative deployment guide is
> **[MODAL_DEPLOYMENT.md](./MODAL_DEPLOYMENT.md)** (canonical target: Modal).
> This file is kept as a pointer so older links keep working.

Canonical release path in one line: configure the four Modal secrets
(`littlenet-ai-secrets`, `littlenet-web-secrets`, `littlenet-r2`,
`littlenet-email`), then run the **Deploy & Validate LittleNet Live** workflow
(`.github/workflows/deploy-modal.yml`):

```text
AI deploy → web deploy → PostgreSQL init/migrations → quiz seed
→ preflight → /healthz + /readyz → Playwright smoke → live APK artifact
```

Database rule: **dbmate is the single migration owner.** Fresh database:

```bash
python tools/init_db.py
dbmate --no-dump-schema --migrations-dir db/migrations up
```

Existing database: `dbmate up` only. Never run `dbmate up` alone on an empty
database.

Manual diagnostics (see the canonical guide for the full sequence):

```bash
python -m pip install -r requirements-modal.txt
modal token info
modal deploy modal_ai.py
modal deploy modal_web.py
modal run modal_web.py --init-db
modal run modal_web.py --seed
modal run modal_web.py --preflight
```

Then require `GET /healthz` = HTTP 200 and `GET /readyz` = HTTP 200/ready.
