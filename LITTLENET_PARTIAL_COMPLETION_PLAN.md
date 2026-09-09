# LITTLENET PARTIAL STATES COMPLETION PLAN
Authoritative Baseline: `D:\aitprojects\LittleNet-1-current`
Verification Date: September 9, 2026

## Overview
This plan establishes the exact roadmap to transition all 16 PARTIAL screens into COMPLETE / IMPLEMENTED states across Backend, Database, API, Flutter UI, and Automated E2E test suites.

---

### Priority 1: High-Value Child Social & Messaging Workflows

#### 1. Screen 11: Comments & Replies (Nested Discussion)
- **Rank:** P1
- **Current Implementation:** Flat comments list in `PostDetailScreen` (`screens/stitch_social.dart`).
- **Missing Behavior:** Nested comment replies, "Reply" action on individual comments, threaded visual indentation, and replying-to indicator.
- **Backend/API Required:** Update `POST /api/mobile/v1/kids/posts/<id>/comment` to accept `parent_comment_id`. Update `_comment_rows` in `mobile/stitch_api.py` to return `parent_comment_id` and hierarchically sort replies.
- **DB Migration Required:** Add `parent_comment_id BIGINT REFERENCES comments(comment_id) ON DELETE CASCADE` to `comments` table.
- **Flutter Changes:** Add "Reply" button to comment tiles, replying banner above text field, indented rendering for child replies.
- **Tests Required:** Unit test for nested comments, integration test in `flutter_ui_e2e_test.dart`.
- **Definition of COMPLETE:** Child can reply to another child's comment, comments render hierarchically, and AI scans all replies.

#### 2. Screen 32: New Message Flow
- **Rank:** P1
- **Current Implementation:** `MessagesPage` only displays existing conversation threads.
- **Missing Behavior:** Dedicated "New Message" button that opens an approved-friend selector to initiate a fresh 1:1 conversation.
- **Backend/API Required:** Uses existing `GET /api/mobile/v1/kids/discover` (filtered to approved network).
- **DB Migration Required:** None.
- **Flutter Changes:** Add FloatingActionButton (+) in `MessagesPage` leading to `NewMessageScreen` listing approved network friends with instant chat launcher.
- **Tests Required:** Test in `flutter_ui_e2e_test.dart`.
- **Definition of COMPLETE:** Child can tap (+), select an approved friend from their network, and immediately open `ChatPage`.

#### 3. Screen 34: Chat Info, Block & Report
- **Rank:** P1
- **Current Implementation:** Generic bottom sheet report action.
- **Missing Behavior:** Dedicated `ChatInfoScreen` displaying friend profile, mutual connections, media shared in chat, mute toggles, block action, and safety report.
- **Backend/API Required:** `POST /api/mobile/v1/kids/users/<id>/block` and `/report`.
- **DB Migration Required:** None (`blocked_users` and `reports` exist).
- **Flutter Changes:** Add `ChatInfoScreen` reachable from ChatPage AppBar info button.
- **Tests Required:** Test in `flutter_ui_e2e_test.dart`.
- **Definition of COMPLETE:** Child can view chat safety info, mute notifications, and block or report directly from conversation.

#### 4. Screen 35: Unsafe Message Warning
- **Rank:** P1
- **Current Implementation:** Toast notification when message is held for review.
- **Missing Behavior:** Visual in-thread warning card for messages held in moderation or flagged by client-side heuristic.
- **Backend/API Required:** Returns `moderation_status` ('ALLOWED', 'REVIEW', 'BLOCKED') in message stream.
- **DB Migration Required:** None (`child_messages.moderation_status` exists).
- **Flutter Changes:** In `ChatPage`, display an educational shield banner when message is pending safety review or blocked.
- **Tests Required:** Tested in `test_real_service_e2e.py` and `flutter_ui_e2e_test.dart`.
- **Definition of COMPLETE:** Both sender and recipient see clear safety state indicators on flagged messages.

#### 5. Screen 39: Followers / Following / Friends List
- **Rank:** P1
- **Current Implementation:** Count badges on `ProfilePage` without clickable list views.
- **Missing Behavior:** Tapping 'Friends' or 'Following' count opens a tabbed list screen of connected users.
- **Backend/API Required:** `GET /api/mobile/v1/kids/network` returning mutual friends and following list.
- **DB Migration Required:** None (`followers` exists).
- **Flutter Changes:** Implement `FriendsListScreen` with "Friends" and "Following" tabs, reachable by tapping counts on profile.
- **Tests Required:** Test in `flutter_ui_e2e_test.dart`.
- **Definition of COMPLETE:** Child can tap friends count and see all approved mutual connections.

---

### Priority 2: Creation & Safety Pre-Check Flows

#### 6. Screen 13: Post Preview & AI Safety Check
- **Rank:** P2
- **Current Implementation:** Inline creation form in `CreatePostPage`.
- **Missing Behavior:** Pre-publish preview modal with content preview and AI safety badge.
- **Flutter Changes:** Add `PostPreviewDialog` showing card preview and safety badge before upload.
- **Definition of COMPLETE:** Child reviews visual card and safety guarantee before submitting.

#### 7. Screen 19: Story Safety Check & Publish
- **Rank:** P2
- **Current Implementation:** Inline creation form in `StoryEditorScreen`.
- **Missing Behavior:** Explicit safety preview modal with privacy reminder.
- **Flutter Changes:** Add safety confirmation step in `StoryEditorScreen`.
- **Definition of COMPLETE:** Story preview confirms privacy shielding before publishing.

#### 8. Screen 21: Reel Comments Sheet
- **Rank:** P2
- **Current Implementation:** Reel comment icon triggers toast.
- **Missing Behavior:** Modal bottom sheet showing reel comments with real-time add/reply actions.
- **Flutter Changes:** Wire comment icon in `_StitchReelPane` to open `_CommentsSheet`.
- **Definition of COMPLETE:** Child can view and add comments directly while watching reels.

#### 9. Screen 24: Reel Preview & Moderation
- **Rank:** P2
- **Current Implementation:** Form fields in `ReelEditorScreen`.
- **Missing Behavior:** Visual thumbnail and metadata preview card before reel submission.
- **Flutter Changes:** Add `ReelPreviewScreen` with educational topic tag and safety badge.
- **Definition of COMPLETE:** Child sees reel preview before upload.

#### 10. Screen 25: Reel Detail / Share
- **Rank:** P2
- **Current Implementation:** Save button only on reel card.
- **Missing Behavior:** Full share sheet with safe deep link copy and report action.
- **Flutter Changes:** Wire share icon to open `showSharePostSheet`.
- **Definition of COMPLETE:** Child can share or save reel via native bottom sheet.

#### 11. Screen 38: Edit Profile Screen
- **Rank:** P2
- **Current Implementation:** Simple popup alert dialog in `ProfilePage`.
- **Missing Behavior:** Full-page `EditProfileScreen` with avatar preview, bio guidelines, school/class pickers.
- **Flutter Changes:** Create `EditProfileScreen`.
- **Definition of COMPLETE:** Dedicated profile editor with safety hints against personal PII.

---

### Priority 3: Learning & Parent Administration

#### 12. Screen 9: Feed Tabs (All / Friends / Learning)
- **Rank:** P3
- **Current Implementation:** Single blended feed in `_StitchHomePage`.
- **Missing Behavior:** Quick filter chips (All, Friends, Science, Art) above feed.
- **Flutter Changes:** Add horizontal category filter chips in `_StitchHomePage`.
- **Definition of COMPLETE:** Child can tap 'Science' or 'Friends' to filter feed.

#### 13. Screen 44: Educational Feed / Reels
- **Rank:** P3
- **Current Implementation:** General reels list.
- **Missing Behavior:** Filter toggle to view only Educational & STEM reels.
- **Flutter Changes:** Add educational filter badge in reels view.
- **Definition of COMPLETE:** Child can toggle to strictly educational reels.

#### 14. Screen 45: Quiz List
- **Rank:** P3
- **Current Implementation:** Single quiz card in `LearningScreen`.
- **Missing Behavior:** Expandable list of available quizzes with difficulty ratings.
- **Flutter Changes:** Expand `LearningScreen` to list multiple grade-appropriate quizzes.
- **Definition of COMPLETE:** List of quizzes with play button and completion badges.

#### 15. Screen 47: Learning Challenges
- **Rank:** P3
- **Current Implementation:** Challenge card in `LearningScreen`.
- **Missing Behavior:** Dedicated challenge list with XP rewards and participant counts.
- **Flutter Changes:** Expand challenge section with active challenges.
- **Definition of COMPLETE:** Child can pick and complete learning challenges.

#### 16. Screen 57: Smart Controls (Parent Curfew & Locks)
- **Rank:** P3
- **Current Implementation:** Slider for daily screen time limit.
- **Missing Behavior:** Bedtime curfew, school hours lockout, instant freeze button.
- **Flutter Changes:** Add Quick Freeze switch and Quiet Hours configuration in `ParentControls`.
- **Definition of COMPLETE:** Parent can toggle instant freeze and quiet hours directly.

#### 17. Screen 60: Moderation Review Detail
- **Rank:** P3
- **Current Implementation:** Dialog in `_AdminReviews`.
- **Missing Behavior:** Detailed review screen with full AI signals payload and audit history.
- **Flutter Changes:** Add `AdminReviewDetailScreen`.
- **Definition of COMPLETE:** Admin views complete safety signal breakdown before decision.
