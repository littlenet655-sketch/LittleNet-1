# LittleNet V2 Route & Screen Migration Matrix

## Overview
This document maps every legacy screen from `mobile_flutter/lib/screens/` to its corresponding V2 native architecture under `mobile_flutter/lib/features/`, along with the associated routes, backend APIs, and current implementation status.

---

## 1. Authentication & Onboarding Flow

| Old Screen | V2 Screen | Route | Backend API | Status |
| :--- | :--- | :--- | :--- | :--- |
| `auth.dart` (`LoginScreen`) | `features/auth/login_screen.dart` (`LoginScreen`) | `/login`, `/` | `POST /api/mobile/v1/auth/login` | **MIGRATED & VERIFIED** |
| `auth.dart` (`ParentRegisterScreen`) | `features/auth/parent_signup_screen.dart` (`ParentSignupScreen`) | `/parent/signup` | `POST /api/mobile/v1/auth/register-parent` | **MIGRATED & VERIFIED** |
| `auth.dart` (`VerifyEmailOtpScreen`) | `features/auth/email_otp_screen.dart` (`EmailOtpScreen`) | `/parent/otp` | `POST /api/mobile/v1/auth/verify-email-otp` | **MIGRATED & VERIFIED** |
| `auth.dart` (`ParentLivenessScreen`) | `features/auth/parent_liveness_screen.dart` (`ParentLivenessScreen`) | `/parent/liveness` | `POST /api/mobile/v1/auth/parent-liveness` | **MIGRATED & VERIFIED** |
| `kids_onboarding.dart` (`ChildEnrollmentScreen`) | `features/parent/child_enrollment_screen.dart` (`ChildEnrollmentScreen`) | `/parent/children/add`, `/parent/add-child` | `POST /api/mobile/v1/parent/children` | **MIGRATED & VERIFIED** |

---

## 2. Kids Main Experience

| Old Screen | V2 Screen | Route | Backend API | Status |
| :--- | :--- | :--- | :--- | :--- |
| `kids.dart` (`KidsShell`) | `features/kids/kids_main_shell.dart` (`KidsMainShell`) | `/kids/home`, `/kids/main` | `GET /api/mobile/v1/me` | **MIGRATED & VERIFIED** |
| `kids.dart` (`KidsHomeTab`) | `features/kids/kids_home_screen.dart` (`KidsHomeScreen`) | `/kids/home` (Tab 0) | `GET /api/mobile/v2/kids/feed`, `GET /api/mobile/v1/kids/stories` | **MIGRATED & VERIFIED** |
| `kids.dart` (`KidsDiscoverTab`) | `features/explore/explore_screen.dart` (`ExploreScreen`) | `/kids/explore` (Tab 1) | `GET /api/mobile/v1/kids/explore`, `GET /api/mobile/v1/kids/connections` | **MIGRATED & VERIFIED** |
| `kids_feed.dart` (`KidsFeedTab`) | `features/feed/feed_screen.dart` (`FeedScreen`) | `/kids/feed` | `GET /api/mobile/v2/kids/feed`, `POST /api/mobile/v1/kids/posts/<id>/like` | **MIGRATED & VERIFIED** |
| `kids.dart` (`KidsReelsTab`) | `features/reels/reels_screen.dart` (`ReelsScreen`) | `/kids/reels` (Tab 3) | `GET /api/mobile/v2/kids/feed?surface=REELS` | **MIGRATED & VERIFIED** |
| `kids.dart` (`KidsCreateTab`) | `features/create_post/create_post_screen.dart` (`CreatePostScreen`) | `/kids/create-post` (Tab 2) | `POST /api/mobile/v1/kids/posts` | **MIGRATED & VERIFIED** |
| `kids.dart` (`CommentsDialog`) | `features/feed/comments_sheet.dart` (`CommentsSheet`) | Modal / Sheet | `GET/POST /api/mobile/v1/kids/posts/<id>/comments` | **MIGRATED & VERIFIED** |
| `kids.dart` (`KidsMessagesTab`) | `features/chat/chat_list_screen.dart` (`ChatListScreen`) | `/kids/messages` | `GET /api/mobile/v1/kids/messages/conversations` | **MIGRATED & VERIFIED** |
| `kids.dart` (`ChatScreen`) | `features/chat/chat_conversation_screen.dart` (`ChatConversationScreen`) | `/kids/chat` | `GET/POST /api/mobile/v1/kids/messages/<id>` | **MIGRATED & VERIFIED** |
| `kids.dart` (`KidsProfileTab`) | `features/profile/profile_screen.dart` (`ProfileScreen`) | `/kids/profile` (Tab 4) | `GET /api/mobile/v1/kids/profile` | **MIGRATED & VERIFIED** |
| `kids.dart` (`EditProfileScreen`) | `features/profile/edit_profile_screen.dart` (`EditProfileScreen`) | `/kids/edit-profile` | `POST /api/mobile/v1/kids/profile` | **MIGRATED & VERIFIED** |
| `kids.dart` (`SettingsScreen`) | `features/settings/settings_screen.dart` (`SettingsScreen`) | `/kids/settings` | `GET/POST /api/mobile/v1/kids/settings` | **MIGRATED & VERIFIED** |

---

## 3. Kids Connections & Micro Pages

| Old Screen | V2 Screen | Route | Backend API | Status |
| :--- | :--- | :--- | :--- | :--- |
| `kids.dart` (Follow modal) | `features/profile/followers_following_screen.dart` | `/kids/connections` | `GET /api/mobile/v1/kids/connections` | **MIGRATED & VERIFIED** |
| `kids.dart` (Requests modal) | `features/profile/requests_screen.dart` | `/kids/requests` | `GET/POST /api/mobile/v1/kids/connections/requests` | **MIGRATED & VERIFIED** |
| `kids.dart` (Privacy modal) | `features/settings/subpages/privacy_settings_page.dart` | `/kids/settings/privacy` | `GET /api/mobile/v1/kids/settings` | **MIGRATED & VERIFIED** |
| `kids.dart` (Safety modal) | `features/settings/subpages/safety_settings_page.dart` | `/kids/settings/safety` | Client safety policy info | **MIGRATED & VERIFIED** |
| `kids.dart` (Notifs modal) | `features/settings/subpages/notifications_page.dart` | `/kids/settings/notifications` | `GET /api/mobile/v1/kids/notifications` | **MIGRATED & VERIFIED** |
| `kids.dart` (Screen time modal) | `features/settings/subpages/screen_time_page.dart` | `/kids/settings/screen-time` | `GET /api/mobile/v1/kids/usage` | **MIGRATED & VERIFIED** |
| `kids.dart` (Controls info) | `features/settings/subpages/parent_controls_page.dart` | `/kids/settings/parent-controls` | Client guardian policy info | **MIGRATED & VERIFIED** |
| `kids.dart` (Blocked list) | `features/settings/subpages/blocked_users_page.dart` | `/kids/settings/blocked-users` | `GET /api/mobile/v1/kids/settings/blocked` | **MIGRATED & VERIFIED** |
| `kids.dart` (Muted list) | `features/settings/subpages/muted_users_page.dart` | `/kids/settings/muted-users` | `GET /api/mobile/v1/kids/settings/muted` | **MIGRATED & VERIFIED** |
| `kids.dart` (About) | `features/settings/subpages/help_about_page.dart` | `/kids/settings/help` | App build & legal compliance | **MIGRATED & VERIFIED** |

---

## 4. Learning & Education

| Old Screen | V2 Screen | Route | Backend API | Status |
| :--- | :--- | :--- | :--- | :--- |
| `kids_learning.dart` (`KidsLearningTab`) | `features/learning/learning_screen.dart` (`LearningScreen`) | `/kids/learning` | `GET /api/mobile/v1/kids/learning/modules` | **MIGRATED & VERIFIED** |
| `kids_learning.dart` (`QuizScreen`) | `features/quiz/quiz_screen.dart` (`QuizScreen`) | `/kids/quiz` | `GET/POST /api/mobile/v1/kids/quiz/<id>` | **MIGRATED & VERIFIED** |

---

## 5. Parent Dashboard & Guardian Controls

| Old Screen | V2 Screen | Route | Backend API | Status |
| :--- | :--- | :--- | :--- | :--- |
| `parent.dart` (`ParentShell`, `DashboardTab`) | `features/parent/parent_dashboard_screen.dart` | `/parent/dashboard` | `GET /api/mobile/v1/parent/dashboard` | **MIGRATED & VERIFIED** |
| `parent.dart` (`ControlsTab`) | `features/parent/parent_controls_screen.dart` | `/parent/controls` | `GET/POST /api/mobile/v1/parent/children/<id>/controls` | **MIGRATED & VERIFIED** |
| `parent.dart` (`SafetyTab`) | `features/parent/parent_safety_review_screen.dart` | `/parent/safety-reviews` | `GET/POST /api/mobile/v1/parent/safety-reviews` | **MIGRATED & VERIFIED** |
| `parent.dart` (`RequestsTab`) | `features/parent/parent_follow_requests_screen.dart` | `/parent/follow-requests` | `GET/POST /api/mobile/v1/parent/follow-requests` | **MIGRATED & VERIFIED** |

---

## 6. Moderator & Administration

| Old Screen | V2 Screen | Route | Backend API | Status |
| :--- | :--- | :--- | :--- | :--- |
| `admin.dart` (`AdminShell`) | `features/moderator/moderator_main_shell.dart` | `/moderator/main`, `/moderator/queue` | Server-side role gating | **MIGRATED & VERIFIED** |
| `admin.dart` (`AdminDashboard`) | `features/moderator/moderator_dashboard_screen.dart` | `/moderator/dashboard` | `GET /api/mobile/v1/admin/dashboard` | **MIGRATED & VERIFIED** |
| `admin.dart` (`AdminReviews`) | `features/moderator/moderation_queue_screen.dart` | `/moderator/queue` | `GET /api/mobile/v1/admin/reviews` | **MIGRATED & VERIFIED** |
| `admin.dart` (Review card detail) | `features/moderator/incident_detail_screen.dart` | `/moderator/incident` | `GET/POST /api/mobile/v1/admin/reviews/<id>` | **MIGRATED & VERIFIED** |
| `admin.dart` (`AdminUsers`) | `features/moderator/user_admin_screen.dart` | `/moderator/users` | `GET /api/mobile/v1/admin/users`, `POST /status` | **MIGRATED & VERIFIED** |
| `admin.dart` (`AdminAudit`) | `features/moderator/moderator_audit_screen.dart` | `/moderator/audit` | `GET /api/mobile/v1/admin/audit` | **MIGRATED & VERIFIED** |

---

## Summary
- **100% of user flows** have a dedicated, test-covered V2 replacement.
- Zero fallback to legacy `screens/*.dart` files is required.
- The router (`AppRouter`) can safely wire directly to V2 native screens exclusively.
