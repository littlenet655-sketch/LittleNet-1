# LittleNet  -  Child Centric Social Platform with AI-based Content Filtering

[![Project Status: Release Candidate](https://img.shields.io/badge/Status-Release%20Candidate-yellow.svg)](#release-status)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20Android%20APK%20%7C%20Cloud%20GPU-blue.svg)](#mobile-android-apk)
[![AI Safety](https://img.shields.io/badge/AI%20Safety-Text%20%7C%20Image%20%7C%20Video-orange.svg)](#multi-modal-ai-content-filtering-architecture)
[![Database](https://img.shields.io/badge/Database-PostgreSQL-3ECF8E.svg)](#database-architecture)

---

### 🎓 Academic Information
* **Institution**: Adichunchanagiri Institute of Technology, Chikkamagaluru  -  577102
* **Department**: Department of Computer Science & Engineering (Data Science)
* **Project Type**: Major Project Phase II Presentation (2025 - 2026)
* **Group Number**: `DSPG06`
* **Under the Guidance of**: Prof. Harshitha HD
* **Presented By**:
  - **ATHMIYA D** (`4AI23CD004`)
  - **PRAGNA G SHENOY** (`4AI23CD037`)
  - **ROHINI L GOWDA** (`4AI23CD043`)
  - **SANGEETHA M** (`4AI23CD047`)

---

## 🌟 Executive Abstract

**LittleNet** is a modern, child-centric social networking ecosystem designed from the ground up to protect children aged 6 - 16 while offering an engaging, interactive space to share creativity, learn, and socialize safely.

Traditional platforms expose minors to severe risks including cyberbullying, mature content, online predators, and uncontrolled screen time. LittleNet solves these challenges through **real-time, multi-modal AI content filtering**, a **parent-first approval paradigm**, and **biometric child authentication**:

* **Multi-Modal AI Safety Engine**: Combines text/PII safety with visual adult-content, semantic and dangerous-object detection for TEXT/IMAGE/VIDEO before child visibility. Standalone audio moderation is disabled; video audio is stripped before persistence.
* **Parental Command Center**: Real-time push alerts, granular screen time limits, quiet-hour lockdowns, and pending content approval queues.
* **Kid-Safe Mobile Experience**: Native Android APK with camera-based biometric face login, educational Reels, STEM quizzes, and restricted stranger-discovery algorithms.

---

## 🚦 Release Status

The source and CI gates are green, but the current cloud deployment is **not yet verified live**. The latest `Deploy & Validate LittleNet Live` run stopped before deployment because GitHub Actions is missing `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET`.

The intended release stack is Flask/Jinja web on Modal, protected Modal T4 AI, external PostgreSQL and private Cloudflare R2. Public endpoints must not be called production-ready until the connected workflow completes DB migrations, model warm-up, external preflight, `/readyz`, Playwright smoke and the APK build.

Admin/demo credentials are intentionally not committed or documented; use repository/runtime secrets.

## 📱 Mobile Android APK

- **Package name:** `com.littlenet.app`
- **Target SDK:** Android 35; minSdk 26
- **Final artifact rule:** no production APK is stored in Git. The canonical APK is the GitHub Actions artifact `LittleNet-live-verified-apk`, generated only after the same HTTPS backend passes the live release gate.
- Camera/media access supports face/liveness and image/video upload. Active voice/audio posting is outside the locked runtime.

## 🧠 Multi-Modal AI Content Filtering Architecture

The active moderation contract accepts **TEXT, IMAGE and VIDEO**. Text/PII is checked by deterministic rules plus Detoxify/Presidio. Images and sampled video frames use NudeNet, Falconsai NSFW, CLIP and an OpenImages-capable YOLO dangerous-object policy. PySceneDetect/OpenCV improves video frame selection. DeepFace/MediaPipe support face/liveness flows.

Hard adult/dangerous evidence is blocked before ordinary risk thresholds; uncertainty goes to Parent Review; a total safety outage cannot silently ALLOW content. Uploaded child videos have their audio tracks stripped before R2 persistence because standalone speech/audio moderation is intentionally disabled in the locked build.

## 📂 Complete Project Directory Structure

```text
LittleNet-1/
├── admin/                         # Admin & Safety Moderator Portal
│   ├── api.py                     # Moderator REST endpoints
│   ├── routes.py                  # User management, audit log, & report views
│   └── templates/                 # Admin dashboard, user list, moderation queue
├── ai_server.py                   # Lightweight local microservice wrapper for AI endpoints
├── android/                       # Native Android Project (Java/Gradle)
│   ├── app/
│   │   ├── build.gradle           # SDK 35 compilation specs
│   │   └── src/main/
│   │       ├── AndroidManifest.xml # Permissions (CAMERA, AUDIO, INTERNET)
│   │       ├── java/com/littlenet/app/MainActivity.java # Native WebView container
│   │       └── res/values/strings.xml # Live backend endpoint configuration
│   ├── build.gradle               # Root Gradle build script
│   └── settings.gradle            # Project configuration
├── app.py                         # Flask Application Factory & Core Server
├── auth/                          # Authentication Blueprint
│   ├── routes.py                  # Kids login, parent registration, face enrollment
│   ├── service.py                 # Password hashing (bcrypt) & session security
│   └── templates/                 # Login, register, face login, approval pages
├── child/                         # Child Social Experience
│   ├── routes.py                  # Feed, profile, discover, search routes
│   ├── service.py                 # Post retrieval, interaction logic, screen time enforcement
│   └── templates/                 # Feed, reels, profile, learning, notification pages
├── childMessage/                  # Child-to-Child Secure Messaging
│   ├── routes.py                  # Direct chat with approved friends only
│   ├── service.py                 # Real-time message storage and safety filtering
│   └── templates/                 # Chat UI and thread list
├── config.py                      # Environment variable loader & security policies
├── database/                      # PostgreSQL Storage Layer
│   ├── connection.py              # Threaded connection pooler & query executors
│   ├── schema.sql                 # Complete DDL tables, indexes, constraints
│   ├── seed.sql                   # Educational quizzes, STEM challenges seed data
│   └── upgrade.sql                # Safe incremental migrations
├── modal_ai.py                    # Serverless GPU AI service deployment script (Modal)
├── modal_web.py                   # Serverless Flask Web application runner (Modal)
├── parent/                        # Parental Command Center
│   ├── api.py                     # Real-time alert polling & control endpoints
│   ├── routes.py                  # Parent dashboard, screen time, follow approvals
│   ├── service.py                 # Push alerts, quiet hour scheduling, audit reporting
│   └── templates/                 # Dashboard, safety review, screen time controls
├── quiz/                          # Gamified Child Educational Learning
│   ├── routes.py                  # Quiz taking and scoring endpoints
│   ├── service.py                 # Adaptive question selection
│   └── templates/                 # Interactive quiz card, learning leaderboard
├── safety/                        # Multi-Modal AI Detection Modules
│   ├── audio_service.py           # fail-closed compatibility stub; no active audio model
│   ├── face_service.py            # DeepFace FaceNet512 facial recognition & liveness
│   ├── remote_client.py           # Fail-closed HTTP client to cloud AI service
│   └── visual_service.py          # YOLOv8 + NudeNet + CLIP composite analyzer
├── static/                        # Frontend Assets
│   ├── css/littlenet.css          # Vanilla responsive stylesheet (zero horizontal scroll)
│   ├── favicon.svg                # Child-safe shield brand icon
│   └── js/                        # Client-side validation, live safety polling, face capture
├── templates/                     # Base Layouts & Global Templates
│   ├── 404.html                   # Child-safe 404 Not Found error page
│   ├── 500.html                   # Child-safe 500 Server Error page
│   ├── base.html                  # Global HTML5 shell with CSRF & CSP tokens
│   ├── _icons.html                # Reusable SVG icon components
│   └── _post.html                 # Unified social media post component
├── tools/                         # Automated DevOps & Audit Utilities
│   ├── audit_templates.py         # Verifies 64 templates for zero syntax/CSRF flaws
│   ├── create_admin.py            # CLI tool to initialize admin credentials
│   ├── init_db.py                 # Automated Supabase DDL migration script
│   ├── readiness.py               # 35-point production deployment validation
│   └── scope_check.py             # 41/41 Major Project Phase II feature verification
├── uploadPost/                    # Media Upload & Reels Pipeline
│   ├── routes.py                  # Image, video reel, and audio post creation
│   └── templates/                 # Upload form, full-screen vertical Reels viewer
├── Dockerfile.ai                  # Container definition for AI GPU deployment
├── Dockerfile.web                 # Container definition for Web server deployment
├── requirements-ai.txt            # GPU dependencies (torch, transformers, ultralytics)
├── requirements-core.txt          # Web dependencies (flask, psycopg2, bcrypt)
└── SUBMISSION_SUMMARY.md          # 5-minute Viva & Evaluator Presentation Runbook
```

---

## 🛠️ Local Development & Quick Start

### 1. Clone & Environment Setup
```bash
git clone https://github.com/PragnaGShenoy/LittleNet-1.git
cd LittleNet-1
python -m venv venv
venv\Scripts\activate          # On Windows
source venv/bin/activate       # On Linux/Mac
pip install -r requirements-core.txt
```

### 2. Configure Credentials (`.env`)
Create a `.env` file in the root directory:
```env
DATABASE_URL=postgresql://postgres.your-project-ref:[YOUR_PASSWORD]@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres
SECRET_KEY=your_secret_production_key_here
AI_SERVICE_URL=https://your-modal-app.modal.run
AI_SHARED_SECRET=your_ai_shared_secret_here
BASE_URL=http://localhost:5000
COOKIE_SECURE=0
```

### 3. Initialize Database & Run Web Server
```bash
python tools/init_db.py
python app.py
```
Open **[http://localhost:5000](http://localhost:5000)** in your browser.

---

## 🛡️ Production Security & Safety Policies

* **Fail-Closed Architecture**: If the AI inspection server is unreachable or times out, content is held in pending review rather than published blindly.
* **Strict Child Privacy**: No external tracking cookies, third-party analytics, or behavioral advertisement pixels.
* **Parental Verification Gate**: Children cannot interact with peers until their designated parent confirms their relationship via a single-use crypto-tokenized email link.
* **Hard Block Violations**: Weapons, self-harm, hate speech, and adult imagery are immediately quarantined with zero tolerance.

---

## 🌟 Acknowledgements

We express our sincere gratitude to:
* **Prof. Harshitha HD**, Project Guide, Dept. of CS&E (Data Science), AIT, for continuous guidance and valuable feedback.
* **Dr. C T Jayadeva**, Principal, Adichunchanagiri Institute of Technology.
* The Faculty & Staff of Department of Computer Science & Engineering (Data Science).
