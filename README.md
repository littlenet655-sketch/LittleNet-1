# LittleNet — Child-Centric Social Platform with AI-Based Content Filtering

[![Project Status: Release Candidate](https://img.shields.io/badge/Status-Release%20Candidate-yellow.svg)](#release-status)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20Native%20Flutter%20Android%20%7C%20Cloud%20GPU-blue.svg)](#native-flutter-android-app)
[![AI Safety](https://img.shields.io/badge/AI%20Safety-Text%20%7C%20Image%20%7C%20Video-orange.svg)](#multi-modal-ai-content-filtering-architecture)
[![Database](https://img.shields.io/badge/Database-PostgreSQL-3ECF8E.svg)](#architecture)

---

## 🎓 Academic Information

- **Institution:** Adichunchanagiri Institute of Technology, Chikkamagaluru — 577102
- **Department:** Department of Computer Science & Engineering (Data Science)
- **Project Type:** Major Project Phase II Presentation (2025–2026)
- **Group Number:** `DSPG06`
- **Guide:** Prof. Harshitha HD
- **Presented by:**
  - ATHMIYA D (`4AI23CD004`)
  - PRAGNA G SHENOY (`4AI23CD037`)
  - ROHINI L GOWDA (`4AI23CD043`)
  - SANGEETHA M (`4AI23CD047`)

---

## 🌟 What LittleNet Is

LittleNet is a child-centric social and learning platform for children aged 6–16. It combines a familiar social experience with parent-owned controls, biometric onboarding, age-banded learning breaks and server-side AI safety checks.

The system is built around three user modes:

- **Kids Mode:** feed, stories, reels, posting, discovery, approved-only messaging, profile, notifications, quizzes and learning challenges.
- **Parent Mode:** child accounts, screen-time limits, quiet hours, feature controls, follow approvals, safety-review decisions and activity alerts.
- **Admin/Moderator Mode:** moderation queue, user search, audit trail and human Approve/Block/Escalate actions.

The Android client is now a **genuine Flutter application**. The former Java WebView wrapper has been retired and is no longer a release path.

---

## 🚦 Release Status

The native Flutter build gate now requires all of the following before an APK artifact is accepted:

1. Android runner generation and LittleNet branding.
2. No WebView dependency or Android WebView code.
3. Flutter analysis with actual analyzer errors still fatal.
4. Flutter tests.
5. Release APK build.
6. APK verification for the Flutter ARM64 engine.
7. Package identity `com.littlenet.app`.
8. SHA-256 generation and artifact upload.

The cloud deployment must still pass the separate **Deploy & Validate LittleNet Live** workflow before the hosted backend is called release-verified. That workflow requires Modal credentials, database migration/preflight, public `/healthz` and `/readyz`, browser smoke tests and a native Flutter live APK built against the same HTTPS URL.

Admin/demo credentials are intentionally not committed.

---

## 📱 Native Flutter Android App

The native app lives in `mobile_flutter/` and communicates with Flask through authenticated JSON endpoints under `/api/mobile/v1/*`.

### Android contract

- **Framework:** Flutter / Dart
- **Package name:** `com.littlenet.app`
- **App label:** LittleNet
- **Launcher/splash:** repository LittleNet logo from `static/icons/app_logo.png`
- **Transport:** HTTPS only; Android cleartext traffic disabled
- **Auth storage:** encrypted Flutter secure storage
- **Camera/media:** native camera/gallery access for face setup/login and image/video posting
- **Audio:** standalone voice/audio posting remains outside the locked runtime
- **WebView:** prohibited by CI

### Kids Mode

- Password and Face ID login
- Child face enrollment
- Mandatory onboarding quiz
- Safe feed and stories
- Vertical reels
- Discover/search
- Camera/gallery post, story and reel creation
- Like, comment and save
- Approved-only conversations and chat
- Profile editing
- Notifications
- Learning challenges and quizzes
- Parent-enforced screen time, quiet hours and feature gates

### Parent Mode

- Parent registration, email OTP and adult liveness flow
- Parent dashboard and linked children
- Child account creation
- Screen-time limits
- Reels/stories/messaging/posting/discover controls
- Quiet hours
- Safety review with Approve/Block
- Follow-request approval
- Parent notifications/activity

### Admin/Moderator Mode

- Dashboard metrics
- Moderation queue
- Approve / Block / Escalate
- User search
- Audit trail

---

## 🧠 Multi-Modal AI Content Filtering Architecture

The active moderation contract accepts **TEXT, IMAGE and VIDEO**.

- Text/PII safety uses deterministic policy plus NLP/PII services.
- Images and sampled video frames use visual adult-content, semantic and dangerous-object detection.
- Hard adult or dangerous evidence is blocked before ordinary risk thresholds.
- Uncertain content is placed into review instead of silently allowed.
- Parent and moderator decisions are server-side and auditable.
- DeepFace/MediaPipe support face and liveness flows.
- Standalone audio moderation is retired in the locked college scope; child videos are treated as visual/video content and persisted without active voice posting.

---

## 🏗️ Architecture

```text
Native Flutter Android app                 Web/Jinja client
         │                                       │
         ├──── bearer /api/mobile/v1/* ─────────┤
         │                                       │
         └────────────── HTTPS ──────────────────┘
                         │
                  Flask application
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   PostgreSQL      AI moderation      Private R2 media
        │          Modal GPU/CPU            │
        └────────────────┼──────────────────┘
                         │
             Parent/Admin safety review
```

Safety, screen-time, quiet-hours, approved-connection and moderation decisions remain server-owned so a modified client cannot simply bypass them.

---

## 📂 Important Project Directories

```text
LittleNet-1/
├── mobile_flutter/                 # Native Flutter Android client
│   ├── lib/
│   │   ├── main.dart               # App entrypoint and role routing
│   │   ├── api.dart                # Bearer-auth mobile API client
│   │   ├── widgets.dart            # Shared native media/UI helpers
│   │   └── screens/                # Kids, Parent, Admin native screens
│   └── tool/prepare_android.sh     # Android runner, branding/package hardening
├── mobile/
│   └── api.py                      # /api/mobile/v1/* backend contract
├── admin/                          # Admin/moderator web + services
├── auth/                           # Authentication and parent verification
├── child/                          # Child feed/discovery/profile logic
├── childMessage/                   # Approved-only messaging
├── parent/                         # Parent dashboard/controls/review
├── quiz/                           # Quizzes and learning challenges
├── safety/                         # Text, visual, face and policy services
├── services/                       # Controls, usage, storage, behavior, etc.
├── uploadPost/                     # Post/reel/story persistence pipeline
├── database/                       # PostgreSQL connection/schema/upgrades
├── static/                         # Web assets + canonical LittleNet branding
├── templates/                      # Shared web templates
├── modal_ai.py                     # Modal AI deployment
├── modal_web.py                    # Modal Flask deployment
├── .github/workflows/
│   ├── flutter-native.yml          # Native APK build/verification
│   ├── release-android.yml         # Signed native APK + emulator launch
│   ├── deploy-modal.yml            # Live backend + native live APK gate
│   ├── ci.yml                      # Python/source/security CI
│   └── role-e2e.yml                # Real PostgreSQL role E2E
└── tools/
    ├── audit_all.py
    ├── scope_check.py
    └── readiness.py
```

---

## 🛠️ Local Web Development

```bash
git clone https://github.com/PragnaGShenoy/LittleNet-1.git
cd LittleNet-1
python -m venv venv
```

Windows:

```powershell
venv\Scripts\activate
pip install -r requirements-core.txt
python tools/init_db.py
python app.py
```

Linux/macOS:

```bash
source venv/bin/activate
pip install -r requirements-core.txt
python tools/init_db.py
python app.py
```

Use `.env` / runtime secrets for `DATABASE_URL`, `SECRET_KEY`, AI service credentials, R2 credentials, mail configuration and `BASE_URL`. Do not commit real secrets.

---

## 📲 Native Flutter Development

From `mobile_flutter/`:

```bash
flutter pub get
bash tool/prepare_android.sh
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
flutter build apk --release \
  --dart-define=LITTLENET_API_BASE=https://YOUR-LITTLENET-BACKEND
```

The canonical college APK should come from GitHub Actions rather than a manually modified local build, because CI verifies package identity, branding, Flutter engine presence and the no-WebView contract.

---

## 🛡️ Security & Safety Principles

- **Fail closed:** a safety outage cannot silently publish uncertain child content.
- **Parent-first controls:** screen time, quiet hours and feature access are server-enforced.
- **Approved-only interaction:** messaging requires approved relationships.
- **Private media:** protected media is delivered through authenticated endpoints/storage controls.
- **No embedded secrets:** credentials stay in GitHub/Modal/runtime secrets.
- **No WebView release client:** Android interaction is implemented with Flutter widgets and native plugins.

---

## ✅ Release Workflows

- `LittleNet Native Flutter APK` — analyze, test, build, verify and upload the unsigned/native release artifact.
- `Build & Validate LittleNet Native Android Release` — build, sign, install and launch the native APK on an Android emulator when signing secrets are available.
- `Deploy & Validate LittleNet Live` — deploy backend/AI, migrate/preflight, validate public readiness, browser-smoke the hosted system and build the native APK against that exact live URL.
- `LittleNet CI` — source audits, Python regression, secret scanning and security checks.
- `LittleNet Real PostgreSQL Role E2E` — role-level database-backed integration validation.

---

## 🌟 Acknowledgements

We express our sincere gratitude to **Prof. Harshitha HD**, project guide, the Principal and the faculty/staff of the Department of Computer Science & Engineering (Data Science), Adichunchanagiri Institute of Technology, for their guidance and support.
