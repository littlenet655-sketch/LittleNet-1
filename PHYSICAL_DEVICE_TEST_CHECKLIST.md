# LittleNet Physical Device Verification Checklist

Release APK Path: mobile_flutter/build/app/outputs/flutter-apk/app-release.apk
Build Tools: Android SDK 36.0.0, NDK r28c, Microsoft JDK 17
Target Platform: Android (ARM64-v8a)

This checklist specifies the exact on-device test verification protocol once a physical Android test device is connected via USB debugging.

| # | Check Item | Test Procedure | Expected Result | Verified (Date/Device) |
|---|---|---|---|---|
| 1 | Install APK | db install -r mobile_flutter/build/app/outputs/flutter-apk/app-release.apk | Returns 'Success' without signature/ABI errors | PENDING DEVICE |
| 2 | Launch App | Tap LittleNet launcher icon | Splash screen displays brandmark, transitions to LoginScreen | PENDING DEVICE |
| 3 | Parent Signup & Login | Select Parent role, enter email/password, verify OTP flow | Parent session created, lands on StitchParentShell | PENDING DEVICE |
| 4 | Child Creation | From Parent dashboard, add child with username and age | Child row appears in parent children list with active status | PENDING DEVICE |
| 5 | Child Login | Switch to Child role, login with created child credentials | Auth token restored, lands on StitchKidsShellV2 feed | PENDING DEVICE |
| 6 | Camera Permission & Capture | Open Create Post, tap Camera icon, accept system camera permission | Native camera opens, photo captured and attached | PENDING DEVICE |
| 7 | Gallery Permission & Pick | Open Create Post, tap Gallery icon, select image | Image previews in Create Post form | PENDING DEVICE |
| 8 | Image Upload & Moderation | Submit post with image | Client sends multipart upload, AI moderation runs, post published | PENDING DEVICE |
| 9 | Video Upload | Attach short video (mp4) and submit | Audio stripping/validation occurs, reel/story published | PENDING DEVICE |
| 10 | Feed Persistence | Refresh Kids feed (pull-to-refresh) | Created post appears in feed with media asset rendered | PENDING DEVICE |
| 11 | Reels Playback & Controls | Tap Reels tab, view video reel | Video loops cleanly, heart and comment buttons respond | PENDING DEVICE |
| 12 | Stories Viewing & Posting | Tap Story bubble on home feed | Story viewer presents timed progress bar | PENDING DEVICE |
| 13 | Comments on Post | Open Post Detail, type comment, submit | Comment appears under post with author handle and timestamp | PENDING DEVICE |
| 14 | Follow & Friendship Request | Visit other user profile, tap Follow / Friend Request | Request recorded in DB, requires parent approval if gated | PENDING DEVICE |
| 15 | Direct Messaging (1:1 DM) | Navigate to Messages tab, open conversation, send chat message | Message appears in thread and persists on reload | PENDING DEVICE |
| 16 | Safety Intervention Event | Attempt to submit post with test simulated flagged keyword | Safety toast appears, post held/rejected, event logged | PENDING DEVICE |
| 17 | Parent Alert & Push | Check Parent Alerts screen after safety flag | Notification card displays flagged event for child review | PENDING DEVICE |
| 18 | Screen-Time Restriction Enforcement | Set 15-minute daily limit in Parent controls, exceed limit | Child shell displays Screen-Time Gated restriction banner | PENDING DEVICE |
| 19 | Background / Foreground | Background app for 30s, bring to foreground | Current screen state preserved without crash | PENDING DEVICE |
| 20 | App Kill & Reopen | Force stop app via Android task switcher, relaunch | Auth token restored from secure storage, restores user shell | PENDING DEVICE |
| 21 | Wi-Fi Off / Airplane Mode | Disable network while browsing cached feed | Offline banner displays defensively without app crash | PENDING DEVICE |
| 22 | Network Reconnect & Media Reload | Re-enable Wi-Fi | Feed automatically re-fetches latest media assets | PENDING DEVICE |
