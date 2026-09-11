# LittleNet — Final Submission-Ready Specification (Frozen)

This document is the immutable architectural, product, and operational specification for LittleNet. All development, testing, and release engineering must adhere strictly to these definitions.

---

## 1. Roles
* **Child**: Familiar Instagram-like experience (Home Feed, Stories, Reels, Explore, Profile, Create Post/Reel/Story, Likes, Comments, Saves, Follows, Notifications, 1-on-1 Safe Chat). Access governed continuously by parent controls, screen-time, quiet hours, face security, mandatory quizzes, and AI moderation.
* **Parent**: Manages and monitors linked children. Configures screen limits, quiet hours, feature toggles (Messaging, Reels, Explore, Posting, Stories), connection approvals, safety alerts, and safety-review items.
* **Admin / Moderator**: Platform-level oversight, flagged content, and review queue.

---

## 2. Pinned Technology Stack
| Purpose | Provider / Technology |
| :--- | :--- |
| **Android App** | Flutter Native (`com.example.littlenet_native`) |
| **Target Device** | Motorola Moto G54 5G (Android 15, API 35, `arm64-v8a`, UDID `ZD222F6DQ2`) |
| **Primary API Host** | Northflank (`littlenet-api-dev` on Gunicorn port 8080; `/healthz`, `/readyz`) |
| **Production Database** | Northflank PostgreSQL Addon (Source of Truth; Neon is dev-only) |
| **Media / Object Storage** | Cloudflare R2 (signed direct upload URLs) |
| **Async Job Queue** | Upstash QStash |
| **Heavy AI Moderation** | Modal (NudeNet, Falconsai, CLIP, YOLO, Detoxify, PII/rule engine) |
| **Email / OTP** | Resend |
| **On-Device Face Security** | Google ML Kit (detection/liveness) + MobileFaceNet (local embeddings/comparison) |
| **Physical QA Automation** | Appium + UiAutomator2 |
| **Source Control** | GitHub (`upstream/feature/submission-rebuild-v2`) |

*Rule*: Do NOT add Firebase, Redis, Kafka, ClickHouse, another database, another queue, or another CDN.

---

## 3. Core Architectural Lifecycles

### A. Media Upload Lifecycle
1. Child selects media + caption + category + hashtags + optional coarse location.
2. Flutter requests upload session from Northflank (`POST /api/mobile/v2/uploads/session`).
3. Northflank validates policies and returns a Cloudflare R2 signed upload URL.
4. Flutter streams media directly to R2 quarantine bucket.
5. Flutter notifies Northflank (`POST /api/mobile/v2/uploads/<upload_id>/complete`).
6. Post is created in PostgreSQL with status `PROCESSING`.
7. Northflank dispatches job via Upstash QStash to Modal AI.
8. Modal AI runs multi-model moderation (NudeNet, Falconsai, CLIP, YOLO, Detoxify, PII).
9. Output is evaluated by Policy Engine: `ALLOW`, `REVIEW`, or `BLOCK`.
10. If `ALLOW`: Published to delivery R2, post becomes visible on Profile, Followers Feed, and Explore (if discoverable).

### B. Explore Feed Eligibility
Explore is meant for discovering content beyond existing followers:
* Must be `PUBLISHED` + `moderation_status='ALLOWED'` + `is_safe=TRUE`
* Age-compatible with viewer
* Category allowed by parent controls
* Creator is not blocked or muted
* Parent allows Explore feature
* **Does NOT require following the creator**

### C. Reels Architecture
* Vertical swipe with bounded player architecture (`previous`, `current`, `next`) to prevent OOM / decoder exhaustion.
* Governed by screen-time limits and quiet hours.
* Can display user reels and safe educational video content.

### D. Chat Moderation Lifecycle
* Child A sends message to approved connection Child B.
* Backend intercepts: PII + toxicity + grooming rules.
* `ALLOW` → Delivered to Child B.
* `BLOCK` → Suppressed, sender notified safely.
* `REVIEW` → Routed to parent/moderator dashboard.

### E. Mandatory Quizzes
1. **Onboarding Safety Quiz**: Required for new child accounts; verified against PostgreSQL rows.
2. **Brain-Break Quiz**: Triggered after viewing 4 combined Feed/Reel items (configurable 1–4 by parent). Server-backed counter; cannot be bypassed by restarting or switching tabs.
