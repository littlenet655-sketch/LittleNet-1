# LittleNet Flutter V2 Rebuild Contract

## Goal

Replace the current monolithic Flutter UI with a fresh native Flutter interface without breaking the verified backend contracts or reintroducing WebView code.

## Non-negotiable rules

1. `mobile_flutter/` remains a real native Flutter client. No WebView, remote HTML shell, or embedded browser may replace native screens.
2. Do not delete the current UI before the V2 replacement compiles and its route/feature contract tests pass.
3. Backend APIs, auth state, moderation, R2 media authorization, parent controls, and audit semantics are preserved unless a migration is explicitly reviewed.
4. Whisper/audio remains retired. No standalone audio upload, voice upload, story music, or Whisper dependency is reintroduced.
5. New UI is API-driven. Server-rendered HTML may remain for browser/admin compatibility until each dependency is proven unused; it is not the Android app UI.
6. Every child-facing media surface must receive only server-authorized ALLOWED content.

## V2 target layout

```text
mobile_flutter/lib/
  app/
    app.dart
    router.dart
    theme.dart
  core/
    api/
    auth/
    models/
    widgets/
  features/
    auth/
      login/
      parent_signup/
      otp/
      liveness/
      child_enrollment/
    kids/
      home/
      feed/
      reels/
      create_post/
      likes/
      chat/
      profile/
      settings/
      notifications/
      learning/
    parent/
      dashboard/
      children/
      controls/
      screen_time/
      safety_review/
      notifications/
      settings/
    moderator/
      queue/
      incident/
      audit/
```

## Migration sequence

1. Inventory current Flutter routes/widgets and the API methods each one calls.
2. Create V2 app/theme/router/core API layer without changing runtime entrypoint.
3. Rebuild authentication screens and prove login/session restore.
4. Rebuild Kids shell: home/feed/reels/create/likes/chat/profile/settings.
5. Rebuild Parent shell and moderator/admin shell.
6. Add reel controller pool: current + next + optional previous; prefetch next API page before exhaustion.
7. Run `flutter analyze`, `flutter test`, package/no-WebView checks, and live mobile API smoke.
8. Switch `main.dart` to V2.
9. Only after step 8 is green, delete obsolete Flutter screen files.
10. Re-run release APK build and physical-device walkthrough.

## Old UI deletion gate

The following current files are **replacement candidates**, not immediate deletion targets:

- `mobile_flutter/lib/screens/auth.dart`
- `mobile_flutter/lib/screens/kids.dart`
- `mobile_flutter/lib/screens/kids_feed.dart`
- `mobile_flutter/lib/screens/kids_learning.dart`
- `mobile_flutter/lib/screens/kids_onboarding.dart`
- `mobile_flutter/lib/screens/parent.dart`
- `mobile_flutter/lib/screens/admin.dart`
- presentation-only portions of `mobile_flutter/lib/widgets.dart`

They may be deleted only when no active import/reference remains and the V2 APK passes compile, tests, no-WebView verification, and live API smoke.
