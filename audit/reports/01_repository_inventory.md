# 01 — Repository Inventory Report

**Audited Repository:** `https://github.com/littlenet655-sketch/LittleNet-1`  
**Audited Branch:** `feature/submission-rebuild-v2`  
**Git HEAD SHA:** `6a4a21e03c88b9acdc098cf8d0a3013d996693e3`  
**Date of Audit:** 2026-09-08  

---

## 1. System Overview & Entry Points

| Entry Point | Path | Status | Role / Responsibilities |
| :--- | :--- | :--- | :--- |
| **Flask Web & API** | [`app.py`](file:///d:/aitprojects/LittleNet-1/app.py) | **Active** | Core backend application factory. Registers all blueprints, sets up CSRF, security headers, database pooling, and session configuration. |
| **Modal Web Serverless** | [`modal_web.py`](file:///d:/aitprojects/LittleNet-1/modal_web.py) | **Active** | Serverless entrypoint on Modal for the web application and mobile API endpoints. |
| **Modal AI Service** | [`modal_ai.py`](file:///d:/aitprojects/LittleNet-1/modal_ai.py) | **Active** | Serverless AI inference endpoint for visual, NSFW, adult, and text moderation. Runs on dedicated GPU runtime. |
| **Local AI Fallback** | [`ai_server.py`](file:///d:/aitprojects/LittleNet-1/ai_server.py) | **Active / Standby** | Standalone FastAPI/HTTP microservice for local execution when Modal is offline. |

---

## 2. Blueprint & Route Architecture

The backend consists of **130 validated endpoints** across 9 core blueprints:

```
LittleNet Backend
├── /auth/              -> auth/routes.py, auth/api.py (Parent registration, email OTP, liveness, session)
├── /child/             -> child/routes.py (Child home, onboarding quiz, live safety, discover)
├── /parent/            -> parent/routes.py (Parent dashboard, controls, screen time, child creation)
├── /post/ & /reels/    -> uploadPost/routes.py (Upload, media delivery, reels feed, interactions)
├── /chat/              -> chat/routes.py (Direct peer-to-peer child messaging, parent-approved contacts)
├── /quiz/              -> quiz/routes.py (Educational learning challenges, onboarding quiz)
├── /admin/             -> admin/routes.py (Moderation queue, incident reviews, audit logs)
├── /mobile/api/        -> mobile/api.py (Dedicated bearer-token native JSON API for Flutter)
└── /health & /ready    -> app.py (Readiness and health telemetry)
```

---

## 3. Subsystem Breakdown & File Inventory

### 3.1 Authentication & Identity (`auth/`)
- `auth/routes.py` (475 lines): Web session routes for login, logout, parent registration, OTP verification.
- `auth/api.py` (410 lines): JSON endpoints for registration, OTP resend, adult liveness initiation.
- `auth/parent_email_otp.py` (256 lines): Email OTP state machine, SHA-256 code hashing, 10-min expiry, max 5 attempts.
- `auth/service.py` (840 lines): Password hashing (`hash_password`), user lookup, role verification.
- `auth/child_provisioning.py` (135 lines): Enforces parent-initiated child account creation.
- `auth/verification_provider.py` (182 lines): Adult verification orchestrator.

### 3.2 Mobile Native Client (`mobile_flutter/`)
- `mobile_flutter/pubspec.yaml`: Declares Flutter SDK dependencies (`http`, `flutter_secure_storage`, `camera`, `video_player`). **Zero WebView dependency**.
- `mobile_flutter/lib/main.dart` (178 lines): `LittleNetApp` entry point, session restoration, role routing.
- `mobile_flutter/lib/api.dart` (200 lines): `ApiClient` utilizing `FlutterSecureStorage` with `encryptedSharedPreferences: true`.
- `mobile_flutter/lib/widgets.dart` (250 lines): Reusable native UI components (`NativeMedia`, `Avatar`, `AsyncBody`).
- `mobile_flutter/lib/screens/auth.dart` (554 lines): Native login, parent registration, OTP entry, liveness camera.
- `mobile_flutter/lib/screens/kids.dart` (631 lines): Kids navigation shell, Discover, Profile, Messages, Post creation.
- `mobile_flutter/lib/screens/kids_feed.dart` (677 lines): Kids feed, Story viewer, native vertical Reels player.
- `mobile_flutter/lib/screens/kids_learning.dart` (247 lines): Quizzes, notifications.
- `mobile_flutter/lib/screens/kids_onboarding.dart` (343 lines): Face enrollment, mandatory safety quiz.
- `mobile_flutter/lib/screens/parent.dart` (758 lines): Parent dashboard, child switcher, screen time, category toggles.
- `mobile_flutter/lib/screens/admin.dart` (454 lines): Moderator review queue, audit log viewer.
- `mobile_flutter/tool/prepare_android.sh`: Generates Android runner files with `com.littlenet.app`.

### 3.3 Child Safety & AI Moderation (`safety/`)
- `safety/policy_config.py` (114 lines): Loads and validates `config/safety_policy.yaml`. Fails closed on malformed policy.
- `safety/policy.py`: Central decision engine evaluating visual, audio, text, and metadata signals into `ALLOW`, `REVIEW`, or `BLOCK`.
- `safety/yolo_policy.py` (157 lines): Evaluates 98 configured object labels. Hard block on weapons at 0.45 confidence.
- `safety/nsfw_policy.py`: Adult/NSFW evaluation. Hard block on adult content at 0.40 confidence.
- `safety/visual_service.py` (208 lines): Multimodal visual inspection via CLIP, NudeNet, Falconsai, and YOLO.
- `safety/text_service.py`: Text safety analysis, cyberbullying detection, grooming and severe abuse filters.
- `safety/pii_service.py`: Redacts personal contact information, phone numbers, addresses, and full names.
- `safety/face_service.py`: Adult liveness, age estimation, child face enrollment, anti-spoofing.
- `safety/audio_service.py`: **Retired compatibility shim**. Returns safe status without loading models.

### 3.4 Storage & Media (`services/`, `uploadPost/`)
- `services/object_storage.py` (183 lines): Cloudflare R2 storage adapter. Generates signed URLs with strict TTL. Enforces private bucket.
- `uploadPost/routes.py`: Media upload handling, transaction rollback on safety rejection, fast-start reels delivery.

### 3.5 Database & Migrations (`database/`, `db/migrations/`)
- `database/schema.sql` (299 lines): Base PostgreSQL schema (`users`, `posts`, `likes`, `comments`, `followers`, `child_messages`, `quizzes`, `face_profiles`).
- `db/migrations/`: 6 ordered migrations managed via dbmate:
  - `20260906180000_adopt_dbmate.sql`
  - `20260907001500_content_search_indexes.sql`
  - `20260907142000_audit_p0_p1_hardening.sql`
  - `20260907150000_final_runtime_invariants.sql`
  - `20260908093000_native_admin_escalation.sql`
  - `20260908195500_curated_dataset_foundation.sql`

---

## 4. Dead Modules & Stale Code Inventory

1. **Retired Audio Services**: Standalone audio and story music were retired. `safety/audio_service.py` is safely shimmed to prevent import crashes, but any legacy test mocks should be cleaned up.
2. **Unreferenced Legacy Templates**: 8 Jinja HTML templates (e.g. duplicate landing drafts) are unreferenced by active Python routes. They are retained for documentation parity but marked for safe removal upon V2 cutover.
3. **Curated Recommendations Disconnect**: While `curated_content` tables exist, `services/recommendation.py` currently only samples from `posts`.
