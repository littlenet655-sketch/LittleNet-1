# 13 — Claim vs. Reality Audit Matrix

**Audited Date:** 2026-09-08  
**Context:** College Project Submission Audit — Grounded Evaluation of Features.  

---

| FEATURE | IMPLEMENTED | TESTED | LIVE-PROVEN | PARTIAL / MISSING | FILE EVIDENCE | SAFE TO CLAIM IN COLLEGE DEMO |
| :--- | :---: | :---: | :---: | :---: | :--- | :---: |
| **Parent/Child Accounts** | YES | YES | YES | — | `auth/child_provisioning.py`, `parent/routes.py` | **YES** |
| **Email OTP Gate** | YES | YES | YES | — | `auth/parent_email_otp.py`, `mailg/send_email.py` | **YES** |
| **SMS Authentication** | **NO** | **NO** | **NO** | **SMS NOT IMPLEMENTED** | 0 references in `auth/*.py` or `mobile/*.py` | **NO (Do not claim SMS)** |
| **Adult Liveness Verification** | YES | YES | YES | — | `safety/face_service.py:verify_adult_face` | **YES** |
| **Child Face Login** | YES | YES | YES | — | `safety/face_service.py:verify_face_login` | **YES** |
| **Onboarding Safety Quiz** | YES | YES | YES | — | `quiz/routes.py`, `mobile_flutter/lib/screens/kids_onboarding.dart` | **YES** |
| **Visual Moderation (NSFW)** | YES | YES | YES | — | `safety/visual_service.py`, `safety/nsfw_policy.py` | **YES** |
| **Weapons Detection (YOLO)** | YES | YES | YES | Partial (COCO-80 overlap) | `safety/yolo_policy.py`, `models/yolov8n.pt` | **YES** |
| **80+ YAML Policy Vocabulary** | YES | YES | YES | — | `config/safety_policy.yaml` (98 labels defined) | **YES** |
| **PII & Contact Redaction** | YES | YES | YES | — | `safety/pii_service.py` | **YES** |
| **Grooming & Severe Abuse** | YES | YES | YES | — | `safety/text_service.py`, `config/safety_policy.yaml` | **YES** |
| **Cyberbullying & Toxic NLP** | YES | YES | YES | — | `safety/text_service.py:analyze_text` | **YES** |
| **Posts & Media Upload** | YES | YES | YES | — | `uploadPost/routes.py`, `mobile/api.py` | **YES** |
| **Vertical Video Reels** | YES | YES | YES | — | `uploadPost/templates/reels.html`, `mobile_flutter/lib/screens/kids_feed.dart` | **YES** |
| **Stories** | YES | YES | YES | — | `child/templates/stories_viewer.html`, `mobile/api.py` | **YES** |
| **Direct Peer-to-Peer Chat** | YES | YES | YES | — | `chat/routes.py`, `mobile/api.py` (parent-approved only) | **YES** |
| **Screen Time Limits** | YES | YES | YES | — | `services/behavior.py`, `parent/routes.py` | **YES** |
| **Parent Review Queue** | YES | YES | YES | — | `parent/templates/safety_review.html`, `mobile/api.py` | **YES** |
| **Admin / Moderator Console** | YES | YES | YES | — | `admin/routes.py`, `mobile_flutter/lib/screens/admin.dart` | **YES** |
| **Personalized Recommendations** | YES | YES | YES | Social only | `services/recommendation.py` (diversity + balance) | **YES** |
| **Curated 206-Item Dataset Ingestion**| PARTIAL | YES | NO | **P0 Dataset Blocker** | `tools/dataset_bundle_ingest.py`, Row 120 duplicate | **PARTIAL (Dry-run only)** |
| **Cloudflare R2 Storage** | YES | YES | YES | — | `services/object_storage.py` (Signed URLs, private bucket) | **YES** |
| **Neon PostgreSQL Database** | YES | YES | YES | — | `database/schema.sql`, `db/migrations/` | **YES** |
| **Native Flutter App (No WebView)**| YES | YES | YES | Zero WebView | `mobile_flutter/lib/`, `tools/audit_all.py` | **YES** |
| **Offline Support** | PARTIAL | NO | NO | Caches only | Native secure storage caches tokens; offline feed pending | **NO (Require network)** |
| **Push Notifications** | PARTIAL | YES | YES | In-app only | `mobile/api.py:notifications` (in-app alert queue) | **YES (In-app alerts)** |
| **Whisper / Audio Retirement** | **RETIRED** | YES | YES | Fully retired | `safety/audio_service.py` (passive shim only) | **YES (Retired per spec)** |
