# LittleNet — Phase II Major Project Submission Package
**Department of Computer Science & Engineering (Data Science)**  
**Adichunchanagiri Institute of Technology, Chikkamagaluru – 577102**

---

### 👥 Project Credentials & Team Info
* **Project Title**: LittleNet – Child Centric Social Platform with AI-based Content Filtering
* **Group Number**: `DSPG06`
* **Team Members**:
  - ATHMIYA D (`4AI23CD004`)
  - PRAGNA G SHENOY (`4AI23CD037`)
  - ROHINI L GOWDA (`4AI23CD043`)
  - SANGEETHA M (`4AI23CD047`)
* **Project Guide**: Prof. Harshitha HD

---

## 🌟 1. Live Cloud Deployments (Permanent & 100% Free Tier)

| Service | Technology | Public HTTPS URL | Credentials / Notes |
| :--- | :--- | :--- | :--- |
| **Kids Social App (Web)** | Flask + Responsive PWA | [https://littlenet655--littlenet-web-web.modal.run](https://littlenet655--littlenet-web-web.modal.run) | Publicly accessible worldwide |
| **Moderator & Admin Workspace** | Flask + Live Audit Logs | [https://littlenet655--littlenet-web-web.modal.run/admin-login/](https://littlenet655--littlenet-web-web.modal.run/admin-login/) | **Email**: `admin@littlenet.com`<br>**Password**: `Littlenet@0ait04` |
| **AI Inference Engine** | Modal Cloud (Nvidia Tesla T4 GPU) | [https://littlenet655--littlenet-ai-ai-web.modal.run](https://littlenet655--littlenet-ai-ai-web.modal.run) | PyTorch, Toxic-BERT, Faster-Whisper, NudeNet, YOLOv8, DeepFace |
| **Relational Database** | Supabase PostgreSQL 17 (Singapore) | `aws-0-ap-southeast-1.pooler.supabase.com:6543` | 500 MB permanent free storage, SSL enabled |

---

## 📱 2. Mobile Android APK Package

* **APK File Location (Project Root)**: `D:\aitprojects\LittleNet-1\LittleNet-v1.0-submission.apk`
* **APK File Location (Desktop Shortcut)**: `C:\Users\aksha\Desktop\LittleNet-v1.0-submission.apk`
* **File Size**: `2.24 MB`
* **Package Name**: `com.littlenet.app`
* **Pre-configured Target**: Connects directly to live production backend `https://littlenet655--littlenet-web-web.modal.run/`
* **Hardware Permissions Enabled**:
  - Front Camera (for biometric child face login and live camera capture)
  - Microphone (for voice notes and audio reels)
  - Storage/Media Access (for photo and video sharing)

### How to Install on Android Phones for Viva Demo:
1. Copy `LittleNet-v1.0-submission.apk` to phone via WhatsApp / Google Drive / USB Cable.
2. Tap the file on the phone and tap **Install** (allow "Install from Unknown Sources" if prompted).
3. The LittleNet icon appears in the app drawer ready for the presentation.

---

## 🎯 3. Viva Presentation: Winning 5-Minute Live Demo Walkthrough

When the external examiners ask to see the working project, follow this exact sequence:

### Step 1: Mobile App Launch & Child Biometric Face Login
1. Open the LittleNet app on the phone (or browser).
2. Point the front camera to show **Face Login / Liveness Detection** (powered by DeepFace Facenet512).
3. Show that if the camera fails or lighting is dim, a secure password fallback is provided.

### Step 2: Content Discovery & Educational Reels
1. Show the child's **Personalized Learning Feed**:
   - Educational short video Reels (STEM, science facts, language challenges).
   - Interactive safety and knowledge Quizzes.
2. Show that external global search is restricted so stranger discovery is blocked.

### Step 3: Real-Time Multi-Modal AI Moderation Test (The "Showstopper")
1. **Text Cyberbullying Test**:
   - Try to write a rude or bullying comment (e.g. *"You are ugly and stupid"*).
   - **Result**: The post is instantly intercepted by Toxic-BERT, rejected, and a friendly educational prompt advises: *"Be kind online! Your comment was flagged for harmful language."*
2. **Visual Adult / Weapon Filter Test**:
   - Try to upload an adult photo or weapon picture.
   - **Result**: NudeNet / YOLOv8 flags the media with high confidence and blocks upload.
3. **Audio Transcription Test**:
   - Upload an audio note; Faster-Whisper transcribes speech in real time to ensure no hidden vulgarity exists in the voice track.

### Step 4: Parent Oversight & Screen Time Dashboard
1. Switch to Parent Mode on a laptop or second device.
2. Show the parent approving the child's account via the secure approval link.
3. Show real-time alerts: The parent receives instant notifications whenever inappropriate content attempts were blocked.
4. Show parental controls: Screen time limits and quiet hours settings.

### Step 5: Admin & Safety Audit Portal
1. Open [https://littlenet655--littlenet-web-web.modal.run/admin-login/](https://littlenet655--littlenet-web-web.modal.run/admin-login/).
2. Log in with `admin@littlenet.com` / `Littlenet@0ait04`.
3. Show the examiners the live audit log table, user management, and safety triage queues.
