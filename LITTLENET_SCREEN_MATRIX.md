# LITTLENET CANONICAL SCREEN IMPLEMENTATION MATRIX (61 SCREENS)
Authoritative Baseline: `mobile_flutter/lib/screen_contract.dart`
Verification Date: September 9, 2026
Commit: Milestone 2 (feature/final-production-completion)

Status Legend:
- COMPLETE: Fully verified end-to-end on physical/emulated device.
- IMPLEMENTED_NOT_E2E_VERIFIED: Full Flutter Widget, wired into Shell/Router, connected to Backend API, passes Dart analyze & Flutter test suites.
- PARTIAL: UI exists or inline state implemented, but missing dedicated route or auxiliary actions.
- MISSING: No dedicated Flutter implementation found.
- OBSOLETE: Intentionally retired or superseded by platform safety architecture.

| ID | Screen | Widget / File | Reachable | API Connected | Persistence / Service | Tests | Status |
|---|---|---|---|---|---|---|---|
| 1 | Splash Screen | `main.dart` (`_LaunchScreen`) | YES | N/A | N/A | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 2 | Choose User | `screens/auth.dart` (`LoginScreen` modes) | YES | Yes | `users` | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 3 | Parent Login & Signup | `screens/auth.dart` (`LoginScreen` / `ParentRegistrationScreen`) | YES | `/api/mobile/v1/auth/parent/register` | PostgreSQL + OTP | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 4 | Child Login | `screens/auth.dart` (`LoginScreen` kids mode) | YES | `/api/mobile/v1/auth/login` | PostgreSQL `users` | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 5 | Create Child Account | `screens/parent.dart` (`_AddChildDialog`) | YES | `/api/mobile/v1/parent/children` | PostgreSQL `users` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 6 | Parent-Child Linking & Consent | `screens/parent.dart` (`ParentChildren`) | YES | `/api/mobile/v1/parent/dashboard` | PostgreSQL `parent_child_relationships` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 7 | Face Enrollment / Liveness | `screens/kids_onboarding.dart` / `auth.dart` | YES | `/api/mobile/v1/kids/face/enroll` | PostgreSQL `face_profiles` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 8 | Kids Home Feed | `screens/stitch_kids_shell_impl.dart` (`_StitchHomePage`) | YES | `/api/mobile/v1/kids/home` | PostgreSQL `posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 9 | Feed Tabs | Inline in `_StitchHomePage` | YES | `/api/mobile/v1/kids/home` | PostgreSQL `posts` | `screen_contract_test.dart` | PARTIAL |
| 10 | Post Detail | `screens/stitch_social.dart` (`PostDetailScreen`) | YES | `/api/mobile/v1/kids/home` | PostgreSQL `posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 11 | Comments & Replies | `screens/stitch_social.dart` (`_CommentsSheet`) | YES | `/api/mobile/v1/kids/posts/<id>/comment` | PostgreSQL `comments` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 12 | Create Post | `screens/kids.dart` (`CreatePostPage`) | YES | `/api/mobile/v1/kids/posts` | R2 + PostgreSQL `posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 13 | Post Preview & AI Safety Check | Inline in `CreatePostPage` | YES | `/api/mobile/v1/kids/posts` | Safety Service | `test_real_service_e2e.py` | PARTIAL |
| 14 | Share / Save Sheet | `screens/stitch_social.dart` (`showSharePostSheet`) | YES | `/api/mobile/v1/kids/posts/<id>/save` | PostgreSQL `saved_posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 15 | Report / Hide Sheet | `screens/stitch_social.dart` (`showReportSheet`) | YES | `/api/mobile/v1/kids/posts/<id>/report` | PostgreSQL `reports` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 16 | Story Viewer | `screens/stitch_kids_shell_impl.dart` (`_StoryViewerSheet`) | YES | `/api/mobile/v1/kids/home` | PostgreSQL `posts` (is_story) | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 17 | Create Story | `screens/kids.dart` (`CreatePostPage` story mode) | YES | `/api/mobile/v1/kids/posts` | R2 + PostgreSQL `posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 18 | Story Editor | `screens/creator_editors.dart` (`StoryEditorScreen`) | YES | `/api/mobile/v1/kids/posts` | R2 + PostgreSQL `posts` | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 19 | Story Safety Check & Publish | Inline in `StoryEditorScreen` | YES | `/api/mobile/v1/kids/posts` | Safety Service | `flutter_ui_e2e_test.dart` | PARTIAL |
| 20 | Reels Feed | `screens/stitch_kids_shell_impl.dart` (`_StitchReelsPage`) | YES | `/api/mobile/v1/kids/reels` | PostgreSQL `posts` (is_reel) | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 21 | Reel Comments | Inline in `_StitchReelsPage` | YES | `/api/mobile/v1/kids/posts/<id>/comment` | PostgreSQL `comments` | `screen_contract_test.dart` | PARTIAL |
| 22 | Create Reel | `screens/kids.dart` (`CreatePostPage` reel mode) | YES | `/api/mobile/v1/kids/posts` | R2 + PostgreSQL `posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 23 | Reel Editor | `screens/creator_editors.dart` (`ReelEditorScreen`) | YES | `/api/mobile/v1/kids/posts` | R2 + PostgreSQL `posts` | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 24 | Reel Preview & Moderation | Inline in `ReelEditorScreen` | YES | `/api/mobile/v1/kids/posts` | Safety Service | `flutter_ui_e2e_test.dart` | PARTIAL |
| 25 | Reel Detail / Share | Inline in `_StitchReelsPage` | YES | `/api/mobile/v1/kids/posts/<id>/save` | PostgreSQL `saved_posts` | `wiring_contract_test.dart` | PARTIAL |
| 26 | Explore | `screens/kids.dart` (`DiscoverPage`) | YES | `/api/mobile/v1/kids/discover` | PostgreSQL | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 27 | Search | `screens/search_flow.dart` (`SearchScreen`) | YES | `/api/mobile/v1/kids/discover` | PostgreSQL | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 28 | Search Results | `screens/search_flow.dart` (`SearchResultsScreen`) | YES | `/api/mobile/v1/kids/discover` | PostgreSQL | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 29 | Blocked / Unsafe Search | `screens/search_flow.dart` (`BlockedSearchScreen`) | YES | Client Shield + PII Warning | Safety Service | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 30 | DM Inbox | `screens/kids.dart` (`MessagesPage`) | YES | `/api/mobile/v1/kids/messages` | PostgreSQL `child_messages` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 31 | One-to-One Chat | `screens/kids.dart` (`ChatPage`) | YES | `/api/mobile/v1/kids/chat/<peer_id>` | PostgreSQL `child_messages` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 32 | New Message | Inline in `MessagesPage` | YES | `/api/mobile/v1/kids/messages` | PostgreSQL | `flutter_ui_e2e_test.dart` | PARTIAL |
| 33 | Group Chat | `screens/creator_editors.dart` (`StudyCircleScreen`) | YES | Moderated Circle | PostgreSQL | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 34 | Chat Info / Block / Report | `screens/stitch_social.dart` (`showReportSheet`) | YES | `/api/mobile/v1/kids/posts/<id>/report` | PostgreSQL `reports` | `wiring_contract_test.dart` | PARTIAL |
| 35 | Unsafe Message Warning | Inline in `ChatPage` | YES | Client Shield + Safety Service | PostgreSQL `moderation_events` | `test_real_service_e2e.py` | PARTIAL |
| 36 | My Profile | `screens/kids.dart` (`ProfilePage`) | YES | `/api/mobile/v1/kids/profile` | PostgreSQL `child_profiles` | `flutter_ui_e2e_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 37 | Other User Profile | `screens/stitch_social.dart` (`OtherUserProfileScreen`) | YES | `/api/mobile/v1/kids/profile/<id>` | PostgreSQL `child_profiles` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 38 | Edit Profile | Dialog in `ProfilePage` | YES | `/api/mobile/v1/kids/profile` | PostgreSQL `child_profiles` | `flutter_ui_e2e_test.dart` | PARTIAL |
| 39 | Followers / Following / Friends | Inline in `ProfilePage` & `OtherUserProfile` | YES | `/api/mobile/v1/kids/discover` | PostgreSQL `followers` | `test_real_service_e2e.py` | PARTIAL |
| 40 | Friend / Follow Requests | `screens/parent.dart` (`_FollowRequestsSection`) | YES | `/api/mobile/v1/parent/follow-requests` | PostgreSQL `followers` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 41 | Saved Content | `screens/stitch_social.dart` (`SavedContentScreen`) | YES | `/api/mobile/v1/kids/posts/saved` | PostgreSQL `saved_posts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 42 | Notifications Centre | `screens/stitch_kids_shell_impl.dart` (`NotificationsScreen`) | YES | `/api/mobile/v1/kids/notifications` | PostgreSQL `notifications` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 43 | Learning Hub | `screens/kids_learning.dart` (`LearningScreen`) | YES | `/api/mobile/v1/kids/learning` | PostgreSQL `learning_challenges` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 44 | Educational Feed / Reels | Inline in `_StitchHomePage` & `_StitchReelsPage` | YES | `/api/mobile/v1/kids/home` | PostgreSQL `posts` | `wiring_contract_test.dart` | PARTIAL |
| 45 | Quiz List | Inline in `LearningScreen` | YES | `/api/mobile/v1/kids/quiz` | PostgreSQL `quizzes` | `wiring_contract_test.dart` | PARTIAL |
| 46 | Quiz Play & Result | `screens/kids_learning.dart` (`QuizScreen`) | YES | `/api/mobile/v1/kids/quiz/<id>/answer` | PostgreSQL `child_quiz_attempts` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 47 | Learning Challenges | Inline in `LearningScreen` | YES | `/api/mobile/v1/kids/learning/<id>` | PostgreSQL `learning_challenges` | `wiring_contract_test.dart` | PARTIAL |
| 48 | Safety Centre | `screens/stitch_social.dart` (`SafetyCentreScreen`) | YES | Static Safety Guidance | Local/DB | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 49 | Report User / Content | `screens/stitch_social.dart` (`showReportSheet`) | YES | `/api/mobile/v1/kids/posts/<id>/report` | PostgreSQL `reports` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 50 | Moderation Result | `screens/stitch_social.dart` (`ReportHistoryScreen`) | YES | `/api/mobile/v1/kids/reports` | PostgreSQL `reports` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 51 | Report History / Status | `screens/stitch_social.dart` (`ReportHistoryScreen`) | YES | `/api/mobile/v1/kids/reports` | PostgreSQL `reports` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 52 | Parent Dashboard | `screens/parent.dart` (`ParentDashboard`) | YES | `/api/mobile/v1/parent/dashboard` | PostgreSQL | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 53 | Child Activity | `screens/parent.dart` (`ParentActivity`) | YES | `/api/mobile/v1/parent/dashboard` | PostgreSQL `activity_logs` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 54 | Parent Alerts | `screens/parent.dart` (`ParentSafety`) | YES | `/api/mobile/v1/parent/safety` | PostgreSQL `parent_alerts` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 55 | Parent Review | Inline in `ParentSafety` | YES | `/api/mobile/v1/parent/safety/<id>` | PostgreSQL `moderation_events` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 56 | Screen-Time Dashboard & Controls | `screens/parent.dart` (`ParentControls`) | YES | `/api/mobile/v1/parent/controls/<id>` | PostgreSQL `smart_controls` | `test_real_service_e2e.py` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 57 | Smart Controls | Inline in `ParentControls` | YES | `/api/mobile/v1/parent/time-limit/<id>` | PostgreSQL `smart_controls` | `test_real_service_e2e.py` | PARTIAL |
| 58 | Admin Dashboard | `screens/admin.dart` (`AdminDashboard`) | YES | `/api/mobile/v1/admin/dashboard` | PostgreSQL | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 59 | Moderation Queue | `screens/admin.dart` (`_AdminReviews`) | YES | `/api/mobile/v1/admin/reviews` | PostgreSQL `moderation_events` | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |
| 60 | Moderation Review | Dialog in `_AdminReviews` | YES | `/api/mobile/v1/admin/reviews/<id>` | PostgreSQL `moderation_reviews` | `wiring_contract_test.dart` | PARTIAL |
| 61 | Settings & Language | `screens/stitch_shells.dart` (`ParentSettings`) | YES | Local Preferences | Storage | `wiring_contract_test.dart` | IMPLEMENTED_NOT_E2E_VERIFIED |

## Summary Counts (Authoritative Milestone 2 Verification)
- COMPLETE: 0 (Pending physical on-device verification run)
- IMPLEMENTED_NOT_E2E_VERIFIED: 44
- PARTIAL: 17
- MISSING: 0 (ALL 6 PREVIOUSLY MISSING SCREENS ARE NOW IMPLEMENTED)
- OBSOLETE: 0
Total: 61 Screens
