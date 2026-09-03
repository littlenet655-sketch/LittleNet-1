# LittleNet – Academic Viva Presentation Guide & Screen-to-Model Map

**Major Project Phase II (2025–2026)**  
**Department of Computer Science & Engineering (Data Science)**  
**Adichunchanagiri Institute of Technology, Chikkamagaluru**  
**Group**: `DSPG06` | **Project**: LittleNet

---

## 🧭 1. Screen → File → AI Model Mapping

Use this table during your viva defense to answer questions like: *"Which neural network analyzes the image?"*, *"Where is anti-spoofing implemented?"*, or *"Which file contains the safety decision policy?"*.

| Screen / Feature | Route / Endpoint | Frontend Template | Backend Handler | AI Model / Safety Algorithm |
| :--- | :--- | :--- | :--- | :--- |
| **Kids Home Feed** | `/child/dashboard/` | [`child_dashboard.html`](file:///d:/aitprojects/LittleNet-1/child/templates/child_dashboard.html) | `child/routes.py:dashboard()` | Filtered only: approved friends + `moderation_status='ALLOWED'` |
| **Parent Supervision Portal** | `/verify-parent/<token>/` | [`parent_verify.html`](file:///d:/aitprojects/LittleNet-1/auth/templates/parent_verify.html) | `auth/routes.py:verify_parent()` | **Face Anti-Spoofing & Liveness**: `auth/verification_provider.py` |
| **Child Approval Review** | `/parent/approve-child/<token>/` | [`approve_child.html`](file:///d:/aitprojects/LittleNet-1/auth/templates/approve_child.html) | `auth/routes.py:parent_approve_child()` | Single-use token invalidation + cryptographic audit |
| **Image & Post Upload** | `/child/upload-post/` | [`upload.html`](file:///d:/aitprojects/LittleNet-1/uploadPost/templates/upload.html) | `uploadPost/routes.py:upload_post()` | **Ultralytics YOLOv8n** (weapons) + **FalconsAI NSFW** + **NudeNet** + **OpenAI CLIP** |
| **Voice & Audio Moderation** | `/childMessage/routes.py` | [`chat.html`](file:///d:/aitprojects/LittleNet-1/childMessage/templates/chat.html) | `childMessage/routes.py:send_media()` | **FFmpeg** audio extraction + **faster-whisper** transcription + **Detoxify** toxicity analysis |
| **Reels & Clips Player** | `/reels/` | [`reels.html`](file:///d:/aitprojects/LittleNet-1/child/templates/reels.html) | `child/routes.py:reels()` | Video frame sampling + **YOLOv8** + **NudeNet** + **Detoxify** |
| **Parent Safety Command Center** | `/parent/dashboard/` | [`parent_dashboard.html`](file:///d:/aitprojects/LittleNet-1/parent/templates/parent_dashboard.html) | `parent/routes.py:dashboard()` | Real-time screen-time limits, quiet-hour locking, behavior index |
| **Flagged Content Review** | `/parent/safety-review/` | [`safety_review.html`](file:///d:/aitprojects/LittleNet-1/parent/templates/safety_review.html) | `parent/routes.py:safety_review()` | Multi-signal breakdown (adult/weapon/violence/toxicity) + **Blurred preview toggle** |
| **Biometric Face Login** | `/face-login/` | [`face_login.html`](file:///d:/aitprojects/LittleNet-1/auth/templates/face_login.html) | `auth/routes.py:face_login()` | **DeepFace** facial embeddings + live anti-spoofing verification |
| **STEM & Safety Quizzes** | `/learning/` | [`learning.html`](file:///d:/aitprojects/LittleNet-1/quiz/templates/learning.html) | `quiz/routes.py:learning_hub()` | Adaptive age-tiered question bank (6–8, 9–11, 12–13, 14–18) |

---

## 🎯 2. 5-Minute Viva Demo Script

When demonstrating LittleNet to internal or external examiners, follow this exact sequence:

### Step 1: Show the Kid-Safe Interface (1 minute)
1. Open **[https://littlenet655--littlenet-web-web.modal.run](https://littlenet655--littlenet-web-web.modal.run)** on mobile or desktop.
2. Log in to Kids Mode:
   - **Username**: `ait_star_student`
   - **Password**: `StudentAIT2026!`
3. Point out the child-safe visual design:
   - Warm cream background (`#FFF7ED`), candy-gradient story rings, rounded cards (20px), and bottom navigation (`Home`, `Find`, `Create`, `Clips`, `Me`).
   - Note that there are **no stranger feeds**—only parent-approved connections and educational topics.

### Step 2: Test Content Safety Filtering (1.5 minutes)
1. Navigate to **Create** (`/child/upload-post/`).
2. Upload a benign school image (e.g. books, plants) → AI marks it **Allowed** instantly.
3. Attempt to upload an unsafe sample (or text containing cyberbullying) → AI immediately intercepts:
   - Hard blocks 18+ content or dangerous objects.
   - For ambiguous cases, marks as **REVIEW** and routes to the supervising parent without showing the item on the public feed.

### Step 3: Show the Parent Command Center (1.5 minutes)
1. Log into Parent Mode:
   - **Email**: `mentor_parent@ait.edu`
   - **Password**: `ParentAIT2026!`
2. Demonstrate **Parent Review** (`/parent/safety-review/`):
   - Show the 4 model signal meters: **Adult %**, **Weapon %**, **Violence %**, and **Toxicity %**.
   - Show the **Blurred Media Preview** with the explicit toggle: *"Show flagged media"*. Point out that children never see raw flagged content.
3. Show parental controls:
   - Daily screen-time slider (e.g. 60 mins).
   - Strict mode toggle.
   - Quiet-hours automated lockdown.

### Step 4: Show the Multi-Step Parent Verification Flow (1 minute)
1. Explain the registration security:
   - Child cannot self-approve.
   - Parent receives a secure invitation link.
   - Parent opens the dedicated **Parent Supervision Portal** (`/verify-parent/<token>/`).
   - Uses WebRTC camera for live parent selfie anti-spoofing and enters 12-digit mock Aadhaar ID.
   - Approves child account, transitioning status from `PENDING_APPROVAL` to `ACTIVE`.

---

## 🧠 3. Key Theoretical & Architecture Answers for Viva

**Q1: Why did you choose a multi-modal ensemble instead of a single model?**  
> *"Social media content is rarely unimodal. Harmful content can manifest as text cyberbullying, image nudity, video physical violence, or audio harassment in reels. By combining YOLOv8 (objects), NudeNet & CLIP (visual context), Detoxify (text semantics), and Whisper (speech-to-text), LittleNet detects coordinated multi-modal violations that single models miss."*

**Q2: What is your fail-closed policy, and why is it important for child safety?**  
> *"In safety engineering ([`safety/policy.py`](file:///d:/aitprojects/LittleNet-1/safety/policy.py)), if an AI model times out or the network drops (`total_safety_failure`), LittleNet strictly defaults to BLOCK. In partial failure (`partial_safety_failure`), it routes to parent REVIEW. It NEVER silently allows content when models are down. In child protection, a false positive (flagging benign content for parent check) is acceptable, but a false negative (exposing a child to harm) is catastrophic."*

**Q3: How does LittleNet prevent fake accounts or child impersonation?**  
> *"Every child account must be sponsored and verified by a parent. The parent must complete live selfie anti-spoofing verification and identity verification in the parent portal before the child account is activated. Connections between children must also be mutually approved by their respective supervising parents."*

**Q4: How does the system handle high-latency AI inference without lagging the web server?**  
> *"We implemented an asynchronous deployment split: the web frontend runs in a lightweight container ([`Dockerfile.web`](file:///d:/aitprojects/LittleNet-1/Dockerfile.web) / `requirements-core.txt`) with zero PyTorch overhead, while GPU-intensive neural nets run on an Nvidia Tesla T4 microservice ([`modal_ai.py`](file:///d:/aitprojects/LittleNet-1/modal_ai.py)) with dedicated timeout guards and caching."*
