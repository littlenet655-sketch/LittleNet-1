# LittleNet – Child Centric Social Platform with AI-based Content Filtering

[![Project Status: Production Live](https://img.shields.io/badge/Status-Production%20Live-brightgreen.svg)](#live-cloud-deployments)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20Android%20APK%20%7C%20Cloud%20GPU-blue.svg)](#mobile-android-apk)
[![AI Engine: 7 Models](https://img.shields.io/badge/AI%20Engine-PyTorch%20%7C%20YOLOv8%20%7C%20Whisper%20%7C%20Toxic--BERT-orange.svg)](#multi-modal-ai-content-filtering-architecture)
[![Database](https://img.shields.io/badge/Database-PostgreSQL%2017%20(Supabase)-3ECF8E.svg)](#database-architecture)

---

### 🎓 Academic Information
* **Institution**: Adichunchanagiri Institute of Technology, Chikkamagaluru – 577102
* **Department**: Department of Computer Science & Engineering (Data Science)
* **Project Type**: Major Project Phase II Presentation (2025–2026)
* **Group Number**: `DSPG06`
* **Under the Guidance of**: Prof. Harshitha HD
* **Presented By**:
  - **ATHMIYA D** (`4AI23CD004`)
  - **PRAGNA G SHENOY** (`4AI23CD037`)
  - **ROHINI L GOWDA** (`4AI23CD043`)
  - **SANGEETHA M** (`4AI23CD047`)

---

## 🌟 Executive Abstract

**LittleNet** is a modern, child-centric social networking ecosystem designed from the ground up to protect children aged 6–16 while offering an engaging, interactive space to share creativity, learn, and socialize safely.

Traditional platforms expose minors to severe risks including cyberbullying, mature content, online predators, and uncontrolled screen time. LittleNet solves these challenges through **real-time, multi-modal AI content filtering**, a **parent-first approval paradigm**, and **biometric child authentication**:

* **Multi-Modal AI Engine**: Combines NLP toxicity analysis, computer vision object detection, adult classifier neural nets, and audio speech recognition to inspect all uploaded media before it can ever be viewed by peers.
* **Parental Command Center**: Real-time push alerts, granular screen time limits, quiet-hour lockdowns, and pending content approval queues.
* **Kid-Safe Mobile Experience**: Native Android APK with camera-based biometric face login, educational Reels, STEM quizzes, and restricted stranger-discovery algorithms.

---

## 🚀 Live Cloud Deployments

The platform is permanently hosted on free-tier, high-availability serverless and GPU cloud infrastructure:

| Component | Technology | Live URL | Access / Credentials |
| :--- | :--- | :--- | :--- |
| **Kids Social App (Web / PWA)** | Flask + Responsive PWA | **[https://littlenet655--littlenet-web-web.modal.run](https://littlenet655--littlenet-web-web.modal.run)** | Open to public web & mobile browsers |
| **Admin & Moderator Workspace** | Flask + Live Audit Logs | **[https://littlenet655--littlenet-web-web.modal.run/admin-login/](https://littlenet655--littlenet-web-web.modal.run/admin-login/)** | **Email**: `admin@littlenet.com`<br>**Password**: `Littlenet@0ait04` |
| **AI Inference Engine** | Modal Cloud (Nvidia Tesla T4 GPU) | **[https://littlenet655--littlenet-ai-ai-web.modal.run](https://littlenet655--littlenet-ai-ai-web.modal.run)** | Secured via `X-LittleNet-AI-Key` |
| **Relational Database** | Supabase PostgreSQL 17 (Singapore) | `aws-0-ap-southeast-1.pooler.supabase.com:6543` | SSL Encrypted, Connection Pooling |

---

## 📱 Mobile Android APK

* **Production Binary**: [`LittleNet-v1.0-submission.apk`](file:///d:/aitprojects/LittleNet-1/LittleNet-v1.0-submission.apk)
* **Package Name**: `com.littlenet.app`
* **Size**: `2.24 MB`
* **Target SDK**: Android 35 (Backward compatible down to Android 8.0 Oreo, minSdk 26)
* **Features**:
  - Full-screen native container with zero browser chrome
  - Front camera access for child face login
  - Microphone access for voice reels and audio messages
  - Media picker with image/video upload support

---

## 🧠 Multi-Modal AI Content Filtering Architecture

LittleNet employs a 7-stage neural pipeline running in a dedicated GPU container:

```mermaid
graph TD
    A[Child Upload: Image / Video / Audio / Text] --> B[API Gateway: POST /ai/moderate]
    B --> C{Content Type}
    
    C -->|Text / Captions / Comments| D[Toxic-BERT & Detoxify]
    C -->|Images / Video Keyframes| E[NudeNet 3.4 & Falconsai NSFW]
    C -->|Visual Safety / Weapons| F[YOLOv8 + OpenAI CLIP]
    C -->|Audio Tracks / Voice Notes| G[Faster-Whisper Speech-to-Text]
    
    G -->|Transcribed Text| D
    
    D --> H[Unified Multi-Modal Risk Policy]
    E --> H
    F --> H
    
    H -->|Toxicity Score < 0.35 & Safe| I[STATUS: ALLOW - Instant Publication]
    H -->|Borderline Score 0.35 - 0.70| J[STATUS: REVIEW - Sent to Parent Dashboard]
    H -->|Hard Violations: Adult / Cyberbullying / Weapons| K[STATUS: BLOCK - Hard Blocked & Parent Alert Triggered]
```

### Models Utilized
1. **Detoxify (Toxic-BERT)**: Detects cyberbullying, toxic threats, obscenity, and identity attacks in text.
2. **NudeNet 3.4 Classifier**: Identifies explicit visual content with bounding box and score verification.
3. **Falconsai NSFW Classifier**: High-precision transformer-based secondary visual safety check.
4. **YOLOv8 Object Detection**: Scans for weapons, knives, and sharp dangerous objects.
5. **OpenAI CLIP (ViT-B/32)**: Zero-shot visual content moderation against harmful semantic labels.
6. **Faster-Whisper (Large-v3-Turbo / Base)**: Automatic speech recognition converts spoken words in videos and voice notes to text for NLP triage.
7. **DeepFace (FaceNet512)**: Biometric face verification and liveness detection for child login without requiring memorized passwords.

---

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
│   ├── audio_service.py           # Faster-Whisper audio transcription
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
├── LittleNet-v1.0-submission.apk  # Pre-compiled, installable Android APK binary
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
DATABASE_URL=postgresql://postgres.zjlzygnusxjwdocftwjt:Littlenet%400ait04@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres
SECRET_KEY=littlenet_secret_production_key_2026_super_secure
AI_SERVICE_URL=https://littlenet655--littlenet-ai-ai-web.modal.run
AI_SHARED_SECRET=littlenet_secret_key_2026
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
