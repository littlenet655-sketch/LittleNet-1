# 11 — Deployment Configuration & Cloud Contracts Audit Report

**Audited Date:** 2026-09-08  
**Audit Scope:** Deployment definitions, cloud service topology, environment variable contracts, CI release pipelines, and documentation consistency.  

---

## 1. Cloud Architecture & Target Topology

```
                  ┌─────────────────────────────────────┐
                  │          Client Surfaces            │
                  │   Flutter Android APK / Web Browser │
                  └──────────────────┬──────────────────┘
                                     │ HTTPS
                                     ▼
                  ┌─────────────────────────────────────┐
                  │       Modal Serverless Web          │
                  │           (modal_web.py)            │
                  │     Flask + Gunicorn + Mobile API   │
                  └──────┬───────────┬────────────┬─────┘
                         │           │            │
          Internal HTTPS │           │ SQL        │ Signed URLs
                         ▼           ▼            ▼
             ┌───────────────┐ ┌───────────┐ ┌───────────────┐
             │ Modal GPU AI  │ │  Neon DB  │ │ Cloudflare R2 │
             │ (modal_ai.py) │ │(PostgreSQL│ │(Private Media │
             │ Visual / NLP  │ │ Serverless│ │  Object Store)│
             └───────────────┘ └───────────┘ └───────────────┘
```

---

## 2. Environment Variable Secret Contracts (Names Only)

Zero secret values were exposed or logged during audit. The application contracts require the following configuration keys:

| Subsystem | Required Environment Variables | Verification Status |
| :--- | :--- | :---: |
| **Database** | `DATABASE_URL` | Handled via Neon connection pooler. |
| **Object Storage** | `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | Account ID normalized in `services/object_storage.py`. |
| **Email Delivery** | `RESEND_API_KEY`, `MAIL_FROM` | Utilized by `mailg/send_email.py` for transactional parent OTPs. |
| **Application Core** | `SECRET_KEY`, `LITTLENET_API_BASE`, `LITTLENET_DEVICE` | Enforces secure cookies and HTTPS mobile base URL. |
| **Modal AI Service** | `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET` | Used strictly in GitHub Actions deployment secrets. |

---

## 3. Legacy Deployment Artifacts & Stale Documentation

1. **Railway / Vercel Files**: `railway.toml` and historical static configs are legacy artifacts from earlier prototypes. Primary production runtime is Modal serverless (`modal_web.py` and `modal_ai.py`).
2. **Local vs. CI APK Generation**: While the local Windows host lacks Flutter SDK, automated release pipelines are defined and functional in `.github/workflows/flutter-native.yml` and `.github/workflows/release-android.yml`.
