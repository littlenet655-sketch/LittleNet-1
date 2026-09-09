# LittleNet Stitch UI Replacement

This change replaces the native Flutter presentation layer with the UI system from the uploaded `stitch_instagram_ui_clone` design package while retaining LittleNet's existing backend, role routing, moderation, parent controls, API contracts and secure token storage.

## Source of truth

- `littlenet_wordmark_logo/code.html` — exact LittleNet wordmark and blue face mark.
- `littlenet_61_screen_master_manifest.md` — 61-state navigation/design contract.
- Instagram-style Stitch screens — spacing, white canvas, hairline borders, icon-only navigation, story rings, feed geometry, Reels overlay controls, safety badges, Parent/Admin visual hierarchy.

## Production rules retained

- Native Flutter only; no WebView.
- Existing `/api/mobile/v1/*` endpoints are unchanged.
- Existing Kids, Parent and Admin business logic remains server-authoritative.
- Existing secure token storage and role routing remain intact.
- Existing moderation actions and safety gates are preserved.

## Branding

The Android build script now uses launcher and splash branding derived from the uploaded LittleNet wordmark instead of the retired shield logo. The in-app brand is rendered natively from the same SVG geometry.
