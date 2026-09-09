# LITTLENET SCREEN IMPLEMENTATION MATRIX (Canonical 61-Screen Contract)

Audit Date: 2026-09-09
Authoritative Branch: feature/final-production-completion
Source of Truth: mobile_flutter/lib/screen_contract.dart & mobile_flutter/lib/screens/

Status Categories:
- **COMPLETE**: Fully implemented, wired to real backend, and verified via automated E2E tests.
- **IMPLEMENTED_NOT_E2E_VERIFIED**: Substantially implemented in Flutter widgets, wired to API routes and database tables, but not yet verified with end-to-end device/driver test.
- **PARTIAL**: Implemented as part of another screen (folded), or lacking full sub-features (e.g. comment replies, multi-step editor).
- **MISSING**: No dedicated Flutter screen, API route, or database persistence model exists.
- **OBSOLETE**: Old implementation exists in legacy shell (kids.dart) but is not part of the active runtime shell (StitchKidsShellV2).

| ID | Screen | Widget/file | Reachable | API connected | Persistence/service connected | Test | Status |
|---|---|---|---|---|---|---|---|
| 1 | Splash Screen | _LaunchScreen (main.dart) | YES | N/A | Session restoration via /api/mobile/v1/me | flutter smoke | IMPLEMENTED_NOT_E2E_VERIFIED |
| 2 | Choose User | LoginScreen (screens/auth.dart) | YES | YES (/api/mobile/v1/auth/login) | users | native_smoke_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 3 | Parent Login & Signup | _ParentRegisterView / _ParentLoginView (screens/auth.dart) | YES | YES (/auth/parent/register, /auth/parent/login) | users, otps | auth unit tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 4 | Child Login | _ChildLoginView (screens/auth.dart) | YES | YES (/auth/child/login, /api/face/login) | users, face_profiles | auth unit tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 5 | Create Child Account | ParentChildren (screens/parent.dart) | YES | YES (/parent/children) | users, parent_child_map | test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 6 | Parent–Child Linking & Consent | ParentChildren linking dialogs (screens/parent.dart) | YES | YES (/parent/link-child) | parent_child_map | test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 7 | Face Enrollment / Liveness | FaceEnrollmentScreen (screens/kids_onboarding.dart) | YES | YES (/api/face/register, /api/face/liveness) | face_profiles | liveness unit tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 8 | Kids Home Feed | _StitchHomePage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/home) | posts, child_profiles | wiring_contract_test, test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 9 | Feed Tabs | Inline in _StitchHomePage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/home) | posts | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 10 | Post Detail | PostDetailScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/posts/<id>) | posts, likes, comments | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 11 | Comments & Replies | PostDetailScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/posts/<id>/comment) | comments (top-level only, missing parent_id hierarchy) | test_mobile_authenticated_social_e2e | PARTIAL |
| 12 | Create Post | CreatePostPage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/posts) | posts | wiring_contract_test, test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 13 | Post Preview & AI Safety Check | Inline pre-upload dialog / moderation toast (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/posts) | moderation_events | test_mobile_authenticated_social_e2e | PARTIAL |
| 14 | Share / Save Sheet | _showSaveModal (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/posts/<id>/save) | saved_posts | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 15 | Report / Hide Sheet | _showReportModal (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/reports) | reports, moderation_events | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 16 | Story Viewer | _StitchStoriesRow + PostDetailScreen (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/home) | posts (kind=story) | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 17 | Create Story | CreatePostPage(kind: story) (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/posts) | posts (kind=story) | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 18 | Story Editor | No dedicated canvas/stickers/text editor | NO | Folded into CreatePostPage | posts | None | MISSING |
| 19 | Story Safety Check & Publish | Pre-publish check in CreatePostPage | YES | YES (/api/mobile/v1/kids/posts) | moderation_events | wiring_contract_test | PARTIAL |
| 20 | Reels Feed | _StitchReelsPage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/reels) | posts (kind=reel) | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 21 | Reel Comments | PostDetailScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/posts/<id>/comment) | comments | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 22 | Create Reel | CreatePostPage(kind: reel) (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/posts) | posts (kind=reel) | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 23 | Reel Editor | No dedicated video trimmer/sound editor | NO | Folded into CreatePostPage | posts | None | MISSING |
| 24 | Reel Preview & Moderation | Pre-publish check in CreatePostPage | YES | YES (/api/mobile/v1/kids/posts) | moderation_events | wiring_contract_test | PARTIAL |
| 25 | Reel Detail / Share | Reel action buttons & share sheet | YES | YES (/api/mobile/v1/kids/reels) | posts | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 26 | Explore | Suggested users/content on Home tab | PARTIAL | YES (/api/mobile/v1/kids/discover) | users, child_profiles | native_smoke_test | PARTIAL |
| 27 | Search | Dedicated Search bar / page | NO | Missing mobile search endpoint | search indexes | None | MISSING |
| 28 | Search Results | Results list with user/tag tabs | NO | Missing mobile search endpoint | search indexes | None | MISSING |
| 29 | Blocked / Unsafe Search | Safe search refusal / educational warning | NO | Server-side gate only | moderation_events | None | MISSING |
| 30 | DM Inbox | MessagesPage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/conversations) | child_conversations | wiring_contract_test, test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 31 | One-to-One Chat | ChatPage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/conversations/<id>/messages) | child_messages | wiring_contract_test, test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 32 | New Message | Start conversation from profile only | PARTIAL | YES (/api/mobile/v1/kids/conversations) | child_conversations | test_mobile_authenticated_social_e2e | PARTIAL |
| 33 | Group Chat | Multi-user group conversation | NO | Missing group endpoints | No group tables in DB | None | MISSING |
| 34 | Chat Info / Block / Report | Block/Report user from chat | PARTIAL | YES (/api/mobile/v1/kids/block, /reports) | blocked_users, reports | moderation tests | PARTIAL |
| 35 | Unsafe Message / Image Warning | Chat message safety refusal warning | PARTIAL | YES (refusal in chat API) | moderation_events | test_mobile_authenticated_social_e2e | PARTIAL |
| 36 | My Profile | ProfilePage (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/profile) | child_profiles | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 37 | Other User Profile | OtherUserProfileScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/users/<id>) | child_profiles, followers | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 38 | Edit Profile | _EditProfileDialog (screens/stitch_kids_shell_impl.dart) | YES | YES (/api/mobile/v1/kids/profile) | child_profiles | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 39 | Followers / Following / Friends | Counts visible on Profile; list UI incomplete | PARTIAL | YES (/api/mobile/v1/kids/followers) | followers | test_mobile_authenticated_social_e2e | PARTIAL |
| 40 | Friend / Follow Requests | Parent UI manages requests; kids list partial | PARTIAL | YES (/parent/friend-requests) | followers, friend_requests | test_mobile_authenticated_social_e2e | PARTIAL |
| 41 | Saved Content | SavedContentScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/saved) | saved_posts | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 42 | Notifications Centre | NotificationsScreen (screens/kids_learning.dart) | YES | YES (/api/mobile/v1/kids/notifications) | notifications | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 43 | Learning Hub | LearningScreen (screens/kids_learning.dart) | YES | YES (/api/mobile/v1/kids/learning) | learning_challenges | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 44 | Educational Feed / Reels | Inline in LearningScreen | PARTIAL | YES (/api/mobile/v1/kids/learning/reels) | learning_challenges | wiring_contract_test | PARTIAL |
| 45 | Quiz List | QuizGateScreen (screens/kids_onboarding.dart) & LearningScreen | YES | YES (/api/mobile/v1/kids/quizzes) | quizzes | quiz tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 46 | Quiz Play & Result | QuizGateScreen (screens/kids_onboarding.dart) | YES | YES (/api/mobile/v1/kids/quizzes/<id>/submit) | quiz_attempts | quiz tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 47 | Learning Challenges | LearningScreen challenge cards (screens/kids_learning.dart) | YES | YES (/api/mobile/v1/kids/learning/<id>/answer) | learning_attempts | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 48 | Safety Centre | SafetyCentreScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/safety) | moderation_events | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 49 | Report User / Content | Report modal dialog (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/reports) | reports | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 50 | Moderation Result | Toast/status banner on submission | PARTIAL | YES (API response status) | moderation_events | test_mobile_authenticated_social_e2e | PARTIAL |
| 51 | Report History / Status | ReportHistoryScreen (screens/stitch_social.dart) | YES | YES (/api/mobile/v1/kids/reports/history) | reports | wiring_contract_test | IMPLEMENTED_NOT_E2E_VERIFIED |
| 52 | Parent Dashboard | ParentDashboard / StitchParentShell (screens/parent.dart, screens/stitch_shells.dart) | YES | YES (/parent/dashboard) | users, parent_child_map | test_mobile_authenticated_social_e2e | IMPLEMENTED_NOT_E2E_VERIFIED |
| 53 | Child Activity | ParentActivity (screens/parent.dart) | YES | YES (/parent/activity) | child_activity_logs | parent tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 54 | Parent Alerts | Notifications in ParentSafety (screens/parent.dart) | YES | YES (/parent/notifications) | parent_notifications | parent tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 55 | Parent Review | ParentSafety (screens/parent.dart) | YES | YES (/parent/safety/reviews) | moderation_events, parent_reviews | parent tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 56 | Screen-Time Dashboard & Controls | ScreenTimeScreen (screens/parent.dart) | YES | YES (/parent/time-limit) | child_time_limits | screen_time tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 57 | Smart Controls | ChildControlsScreen (screens/parent.dart) | YES | YES (/parent/controls) | parent_control_settings | controls tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 58 | Admin Dashboard | AdminDashboard / StitchAdminShell (screens/admin.dart, screens/stitch_shells.dart) | YES | YES (/admin/dashboard) | users, moderation_events | admin tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 59 | Moderation Queue | AdminReviews (screens/admin.dart) | YES | YES (/admin/reviews) | moderation_events | admin tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 60 | Moderation Review | Review action controls (screens/admin.dart) | YES | YES (/admin/reviews/<id>/action) | moderation_reviews | admin tests | IMPLEMENTED_NOT_E2E_VERIFIED |
| 61 | Settings & Language | Settings shells in Parent/Admin; Language selector | PARTIAL | Partial (role settings) | user_preferences | None | PARTIAL |

## SUMMARY COUNTS (Canonical 61 Screens)

| Status | Count | Percentage |
|---|---|---|
| **COMPLETE** (E2E device verified) | **0** | 0% |
| **IMPLEMENTED_NOT_E2E_VERIFIED** | **38** | 62.3% |
| **PARTIAL** | **17** | 27.9% |
| **MISSING** | **6** | 9.8% |
| **OBSOLETE** | **0** | 0% |
| **TOTAL CANONICAL STATES** | **61** | 100% |

### Breakdown of MISSING Screens (6):
1. **Screen 18**: Story Editor (dedicated creative canvas, stickers, text overlays)
2. **Screen 23**: Reel Editor (dedicated video trimmer, audio selection)
3. **Screen 27**: Search (dedicated search landing with discovery categories)
4. **Screen 28**: Search Results (tabbed user, post, challenge search results)
5. **Screen 29**: Blocked / Unsafe Search (educational safety intervention screen)
6. **Screen 33**: Group Chat (multi-user group messaging and group management)
