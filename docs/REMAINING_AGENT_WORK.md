# LittleNet Remaining Agent Work

This file is the execution handoff after the evidence-based Capy audit and the safe foundation fixes in `chatgpt/submission-foundation-fixes`.

## Rules for every agent

- Base new work on the latest reviewed branch/PR, not stale `main`.
- Do not deploy Modal, modify production Neon/R2, rotate secrets, or push directly to `main`.
- Do not reintroduce Flutter, WebView-as-app, QStash, or a replacement backend stack.
- Do not weaken/delete/skip tests merely to make CI green.
- Use disposable PostgreSQL for backend integration tests.
- Keep all safety decisions fail-closed.
- Every PR must list tests run and remaining risks.

## Agent A — P0 backend state machine + face authentication

### Goal
Finish the backend work that cannot be safely completed with static GitHub edits alone.

### Required changes

1. **Child face enrollment**
   - `/api/mobile/v1/kids/face/enroll` must fail if liveness/embedding generation fails.
   - Never persist `[]`, zero, NaN, empty, or otherwise invalid embeddings.
   - Successful enrollment must persist the real Facenet512 embedding first, then return success.
   - A failed enrollment must not clear the Kids Mode face gate.

2. **Face-first login**
   - The supported child face-login path must require a fresh camera image/liveness check and `safety.face_service.verify` against the enrolled embedding.
   - The HMAC/device challenge may remain only as a clearly named optional device-auth mechanism; possession of `biometric_key` must never be described or accepted as fresh face authentication.
   - Add tests for wrong face, spoof/liveness failure, no enrollment, valid face, expired/replayed challenge, and invalid stored embedding.

3. **Upload completion transaction/idempotency**
   - Lock the upload session row or otherwise make completion atomic.
   - Add/verify uniqueness for `posts.source_media_path` so concurrent completion cannot create duplicate posts.
   - Do not permanently consume an upload before background dispatch is known to be durable/recoverable.
   - On spawn failure, preserve a retryable state and expose an idempotent retry/redrive path.
   - Add a stale `UPLOADED`/`PROCESSING` reaper/redrive mechanism.

4. **R2 verification**
   - Compare actual object byte size to `expected_size_bytes` with a defined safe tolerance (prefer exact for direct PUT unless provider metadata proves otherwise).
   - Validate stored content type/MIME against the upload session.
   - Use the adapter's actual metadata keys consistently (`content_length`, etc.).

5. **REVIEW lifecycle**
   - REVIEW media must remain private/quarantined.
   - Parent/admin preview must be authorized and signed without exposing REVIEW media to child feeds.
   - APPROVE must sanitize/promote the bytes into the published namespace, persist `media_path`/poster, set `moderation_status='ALLOWED'`, `processing_status='ALLOWED'`, and make the post visible.
   - BLOCK must delete/invalidate quarantine media and keep it inaccessible.
   - Approval must verify the reviewing parent owns the child (or admin role is authorized).

6. **Sanitization**
   - Image sanitization exceptions must fail the job; never publish original EXIF-bearing bytes as a fallback.
   - Video sanitization/transcoding failure must fail closed; never promote unsanitized original video.

### Mandatory tests

- Fresh PostgreSQL bootstrap + every dbmate migration.
- Full backend test suite.
- Face enrollment valid/invalid/liveness paths.
- Face login valid/wrong/spoof/no-enrollment.
- Concurrent upload completion.
- Modal spawn failure + retry/redrive.
- Stale processing redrive.
- R2 size/MIME mismatch.
- ALLOWED path.
- REVIEW -> APPROVED path.
- REVIEW -> BLOCKED path.
- BLOCKED/REVIEW media authorization.
- Sanitization failure paths.

### Exit gate
Do not hand off to mobile implementation until all above tests pass on disposable PostgreSQL.

---

## Agent B — React Native foundation + complete onboarding

### Depends on
Agent A backend contract being green.

### Goal
Turn `mobile_app` from the current health shell into the real application foundation.

### Required work

- React Navigation roots/stacks for unauthenticated, Child, Parent, Admin.
- SecureStore token/session persistence and cold-start restoration.
- Centralized API client with timeout, cancellation, normalized errors, centralized 401 logout, retry/backoff only for safe requests.
- TanStack Query (or equivalent) for server state/invalidation.
- NetInfo/AppState integration; suspend polling/background refresh when app is not foregrounded.
- Shared design tokens/components: typography, buttons, forms, cards, avatars, skeletons, empty/error/offline/disabled states.
- Parent registration -> OTP -> resend -> guardian liveness/adult verification -> child creation -> dashboard.
- Child login/password fallback policy approved by backend.
- Child camera face enrollment -> face-first login.
- Mandatory onboarding quiz and recurring feed quiz with navigation restoration after success.
- Explicit UX for 401/403/423/428/503 gates.

### Tests

- Unit/component tests for auth restoration/logout/errors.
- Onboarding navigation tests.
- Parent OTP/liveness contract tests.
- Child face enrollment/login contract tests.
- Quiz persistence/gate tests.
- `npm run typecheck` and `npm run export:android`.

---

## Agent C — Kids social, posting, chat

### Goal
Complete the daily child product after the mobile foundation is stable.

### Required work

- Feed, stories viewer, reels, discover/search.
- Own profile + other-child profile.
- Notifications + mark-read.
- Likes, comments, saves, follow/request/approve/unfollow, mute, block, report.
- Query invalidation so changes appear immediately.
- v2-only posting flow: camera/gallery -> preview -> caption/tags/category -> optional coarse `location_label` -> direct R2 PUT -> completion -> bounded status polling -> ALLOWED/REVIEW/BLOCKED UI -> profile/feed refresh.
- Map mobile `location_label` to backend coarse text storage; never store precise child GPS/live location.
- Conversation list, paginated thread, unread/read state, text/shared-post messaging.
- Add a mobile media-message contract only if it is moderated through the same fail-closed safety pipeline; otherwise explicitly defer it and document the limitation.
- Foreground-only bounded polling, pagination, virtualized lists, posters/thumbnails, signed-URL expiry refresh.

### Tests

- Author post appears in own profile after ALLOWED.
- Eligible approved follower sees ALLOWED post.
- REVIEW/BLOCKED never appear in normal feed.
- Social relationship enforcement.
- Chat approved-only enforcement.
- Message moderation paths.
- Offline/loading/error states.

---

## Agent D — Parent/Admin + performance + evidence

### Goal
Finish control surfaces and prove submission readiness.

### Required work

- Parent dashboard/child summary.
- Safety queue with authorized preview and approve/block.
- Screen-time limits, quiet hours, feature/category controls, follow approvals, activity summaries, parent notifications.
- Verify parent changes affect Child mode without reinstall/relogin where appropriate.
- Admin moderation queue/detail/resolve, account status, audit history.
- Performance pass: pagination, lazy media, virtualized feeds, signed URL refresh, bounded polling, no accidental GPU health wake.
- Android visual pass for every finished screen.
- Remove stale Flutter wording/TODOs/placeholder completion claims/obsolete workflows.
- Create final demo seed instructions, architecture/readme, known limitations, recovery steps, viva/demo sequence, APK/EAS instructions.
- Complete `docs/FINAL_E2E_MATRIX.md` with actual executed evidence only.

### Final exit gate

- Fresh DB bootstrap PASS.
- Full backend suite PASS.
- React Native tests PASS.
- Typecheck PASS.
- Android Expo export PASS.
- Critical Android E2E journeys PASS.
- No production secrets committed.
- No critical journey marked PASS without execution evidence.
