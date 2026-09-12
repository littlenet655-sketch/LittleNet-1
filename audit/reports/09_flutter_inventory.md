# 09 — Flutter Native Client & Android Inventory Report

**Audited Date:** 2026-09-08  
**Audit Scope:** Flutter native architecture, screen-to-API mapping, WebView absence verification, and V2 rebuild replacement matrix.  

---

## 1. Zero WebView Verification

A deep AST and recursive text scan across the entire [`mobile_flutter/`](file:///d:/aitprojects/LittleNet-1/mobile_flutter/) tree confirmed:
- Zero references to `webview_flutter`, `flutter_inappwebview`, `android.webkit.WebView`, or `WebViewClient`.
- All screens utilize native Flutter widgets (`StatefulWidget`, `StatelessWidget`, `CustomScrollView`, `PageView.builder`, `CameraPreview`, `VideoPlayer`).
- `tools/audit_all.py` validated this contract with: `NATIVE FLUTTER ANDROID SOURCE: PASS`.

---

## 2. Screen-by-Screen Inventory & Backend API Mapping

| File Path | Screen / Widget Classes | Lines | Target Backend API Endpoints |
| :--- | :--- | :---: | :--- |
| **`lib/main.dart`** | `LittleNetApp`, `_LaunchScreen`, `_BrandMark` | 178 | `/api/mobile/session/restore/`, `/api/mobile/logout/` |
| **`lib/screens/auth.dart`** | `LoginScreen`, `ParentRegistrationScreen`, `ParentVerificationScreen` | 554 | `/api/mobile/login/`, `/api/mobile/parent/register/`, `/api/mobile/parent/verify-otp/`, `/api/mobile/parent/verify-liveness/` |
| **`lib/screens/kids_onboarding.dart`** | `GateAwareError`, `FaceEnrollmentScreen`, `QuizGateScreen` | 343 | `/api/mobile/child/enroll-face/`, `/api/mobile/child/onboarding-quiz/`, `/api/mobile/child/onboarding-quiz/submit/` |
| **`lib/screens/kids.dart`** | `KidsShell`, `DiscoverPage`, `CreatePostPage`, `MessagesPage`, `ChatPage`, `ProfilePage` | 631 | `/api/mobile/child/discover/`, `/api/mobile/post/create/`, `/api/mobile/chat/conversations/`, `/api/mobile/chat/messages/`, `/api/mobile/child/profile/` |
| **`lib/screens/kids_feed.dart`** | `KidsHomePage`, `StoryBubble`, `StoryViewer`, `PostCard`, `ReelsPage`, `ReelPane` | 677 | `/api/mobile/feed/`, `/api/mobile/reels/`, `/api/mobile/post/like/`, `/api/mobile/post/comments/`, `/api/mobile/post/save/` |
| **`lib/screens/kids_learning.dart`** | `LearningScreen`, `NotificationsScreen` | 247 | `/api/mobile/quizzes/`, `/api/mobile/quiz/submit/`, `/api/mobile/notifications/` |
| **`lib/screens/parent.dart`** | `ParentShell`, `ParentDashboard`, `ChildDashboardCard`, `ParentSafety`, `ParentChildren`, `ChildControlsScreen`, `ScreenTimeScreen`, `ParentActivity`, `ParentSettings` | 758 | `/api/mobile/parent/dashboard/`, `/api/mobile/parent/children/`, `/api/mobile/parent/create-child/`, `/api/mobile/parent/controls/`, `/api/mobile/parent/screen-time/`, `/api/mobile/parent/safety-reviews/` |
| **`lib/screens/admin.dart`** | `AdminShell`, `AdminDashboard`, `AdminReviews`, `AdminUsers`, `AdminAudit`, `_AdminSettings` | 454 | `/api/mobile/admin/moderation-queue/`, `/api/mobile/admin/moderate-post/`, `/api/mobile/admin/audit-logs/` |

---

## 3. V2 Replacement Matrix

Per [`docs/FLUTTER_V2_REBUILD_CONTRACT.md`](file:///d:/aitprojects/LittleNet-1/docs/FLUTTER_V2_REBUILD_CONTRACT.md), current screen files are **replacement candidates** and must **NOT** be deleted until the modular V2 architecture compiles and passes all contract tests:

| Existing File (To Retain During Audit) | Target V2 Modular Destination | Pre-Deletion Acceptance Gate |
| :--- | :--- | :--- |
| `screens/auth.dart` | `features/auth/login/`, `features/auth/parent_signup/`, `features/auth/otp/`, `features/auth/liveness/` | Native auth flow compiles, session restores from `FlutterSecureStorage`, logout works. |
| `screens/kids_onboarding.dart` | `features/auth/child_enrollment/`, `features/kids/onboarding/` | Face enrollment & mandatory quiz pass. |
| `screens/kids_feed.dart` | `features/kids/home/`, `features/kids/feed/`, `features/kids/reels/` | Controller pool handles vertical video swiping without memory leaks. |
| `screens/kids.dart` | `features/kids/chat/`, `features/kids/profile/`, `features/kids/create_post/` | Native media picker, post upload, and direct messaging succeed. |
| `screens/parent.dart` | `features/parent/dashboard/`, `features/parent/controls/`, `features/parent/screen_time/` | Screen-time toggles and safety review alerts function. |
| `screens/admin.dart` | `features/moderator/queue/`, `features/moderator/audit/` | Admin role enforcement and queue moderation work. |
