# LittleNet Physical Device Checklist

This is the required evidence sheet for the preview APK. It must be completed on
an Android device or emulator after installing the APK. Do not change a status
to `PASS` without executing the journey and recording the evidence filename.

Allowed statuses:

- **PASS** — executed successfully with the named evidence.
- **FAIL** — executed and failed with the named evidence.
- **BLOCKED** — could not be executed because a prerequisite, service, device,
  or credential was unavailable.

APK artifact: https://expo.dev/artifacts/eas/Pak-g5Mj08VCdNHHiew-ZHgnSMDEHDzV2vNaqJ5w_FU.apk  
Backend: `https://netlittle2--littlenet-web-web.modal.run`

| # | Journey | Status | Evidence filename | Notes |
|---:|---|---|---|---|
| 1 | Install preview APK | BLOCKED | `device/01_apk_install.png` | APK built; physical device/emulator installation not performed in this environment. |
| 2 | Launch app and confirm backend connection | BLOCKED | `device/02_launch_backend.png` | Requires installed APK and device evidence. |
| 3 | Parent signup form validation | BLOCKED | `device/03_parent_signup.png` | Requires installed APK. |
| 4 | Parent OTP email delivery | FAIL | `device/04_parent_otp_delivery.png` | Live API request returned `email_sent=false`; no inbox evidence exists. |
| 5 | Parent OTP entry and verification | BLOCKED | `device/05_parent_otp_verify.png` | Blocked by failed OTP delivery. |
| 6 | Guardian liveness/adult verification | BLOCKED | `device/06_guardian_liveness.png` | Requires verified OTP and physical camera. |
| 7 | Child enrollment by verified parent | BLOCKED | `device/07_child_enrollment.png` | Requires completed parent verification. |
| 8 | Child face-first login | BLOCKED | `device/08_child_face_login.png` | Requires enrolled face and physical camera. |
| 9 | Mandatory onboarding quiz | BLOCKED | `device/09_onboarding_quiz.png` | Requires child login. |
| 10 | Kids feed shows approved content | BLOCKED | `device/10_feed.png` | Requires child login and seeded/approved data. |
| 11 | Stories viewer and progress | BLOCKED | `device/11_stories.png` | Requires child login and device run. |
| 12 | Reels playback, pause, retry, save | BLOCKED | `device/12_reels.png` | Requires child login and device run. |
| 13 | Explore and search states | BLOCKED | `device/13_explore_search.png` | Requires child login and device run. |
| 14 | Create ALLOW image post | BLOCKED | `device/14_allow_image_post.png` | Requires camera/gallery, R2 upload, and AI service recovery. |
| 15 | ALLOW post refreshes profile/feed | BLOCKED | `device/15_allow_refresh.png` | Requires successful ALLOW post. |
| 16 | REVIEW content stays private | BLOCKED | `device/16_review_privacy.png` | Requires service and device media journey. |
| 17 | BLOCK content is not public | BLOCKED | `device/17_block_privacy.png` | Requires service and device media journey. |
| 18 | Parent safety queue displays REVIEW | BLOCKED | `device/18_parent_review_queue.png` | Requires parent account and review media. |
| 19 | Parent approves REVIEW content | BLOCKED | `device/19_parent_approve.png` | Requires parent queue journey. |
| 20 | Parent disables messaging | BLOCKED | `device/20_parent_messaging_control.png` | Requires parent and child sessions. |
| 21 | Screen-time limit locks child | BLOCKED | `device/21_screen_time.png` | Requires clock-controlled device journey. |
| 22 | Quiet hours lock child | BLOCKED | `device/22_quiet_hours.png` | Requires parent control and device journey. |
| 23 | Category controls affect feed | BLOCKED | `device/23_category_controls.png` | Requires parent control and eligible content. |
| 24 | Follow approval lifecycle | BLOCKED | `device/24_follow_approval.png` | Requires two child accounts and parent approval. |
| 25 | Text chat send/read | BLOCKED | `device/25_text_chat.png` | Requires approved connection. |
| 26 | Chat mute/block/report safety actions | BLOCKED | `device/26_chat_safety.png` | Requires approved connection and device journey. |
| 27 | Notifications and mark-read | BLOCKED | `device/27_notifications.png` | Requires generated notification events. |
| 28 | Saved content and unsave | BLOCKED | `device/28_saved_content.png` | Requires child login and eligible post. |
| 29 | Profile, connections, and comments | BLOCKED | `device/29_profile_social.png` | Requires child login and social fixtures. |
| 30 | Admin moderation queue | BLOCKED | `device/30_admin_queue.png` | Requires admin session and moderation fixtures. |
| 31 | Admin evidence and moderation action | BLOCKED | `device/31_admin_action.png` | Requires admin session and review fixture. |
| 32 | Logout and session restoration | BLOCKED | `device/32_logout_restore.png` | Requires completed authenticated device session. |
| 33 | Safe recommendation filtering | BLOCKED | `device/33_recommendation_safety.png` | Requires eligible content plus block/mute/age controls. |
| 34 | App recovers from offline/API error | BLOCKED | `device/34_offline_error.png` | Requires installed APK and controlled network interruption. |
| 35 | Final clean relaunch and evidence bundle | BLOCKED | `device/35_final_relaunch.png` | Requires all required journeys above and saved screenshots. |

The current non-device evidence is recorded in
`docs/FINAL_E2E_MATRIX.md` and `docs/KNOWN_LIMITATIONS.md`. The `BLOCKED`
entries above are not claims that the implementation is absent; they identify
journeys that still need real device evidence.