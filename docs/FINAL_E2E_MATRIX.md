# LittleNet Final E2E Matrix

Status values:
- **PASS** — journey was executed end-to-end with evidence.
- **FAIL** — journey was executed and failed.
- **UNVERIFIED** — code may exist, but the journey has not been executed end-to-end.

> This matrix is intentionally conservative. Source-presence checks, typechecking, and route existence are not enough to mark a user journey PASS.

Verified on 2026-09-14 against commit `4f9da440` and the subsequent external validation run:

- [LittleNet CI](https://github.com/littlenet655-sketch/LittleNet-1/actions/runs/34761242142): source audit, 347 backend tests, dependency/security checks, and Gitleaks passed.
- [Disposable PostgreSQL role E2E](https://github.com/littlenet655-sketch/LittleNet-1/actions/runs/34761243565): fresh schema/migrations and authenticated Child/Parent/Admin smoke passed.
- [React Native validation](https://github.com/littlenet655-sketch/LittleNet-1/actions/runs/34761244826): 77 tests, typecheck, Android export, and Expo dependency check passed.
- Modal authentication succeeded for the `netlittle2` workspace; `littlenet-web` and `littlenet-ai` were deployed, both expected volumes were present, and the active-container list was empty before and after the bounded probe.

| Journey | Status | Required evidence |
|---|---|---|
| Parent registration | FAIL | Live Modal request with the approved test inbox returned HTTP 200 and created the pending-registration response, but `email_sent=false`; the journey cannot proceed to OTP. |
| Parent email OTP send/verify/resend | FAIL | Live Resend-backed registration was attempted with `E2E_TEST_EMAIL`; no OTP was delivered (`email_sent=false`), so verify/resend could not be completed. |
| Guardian liveness/adult verification | UNVERIFIED | valid + spoof/failure tests |
| Child creation by verified parent | UNVERIFIED | ownership + duplicate validation |
| Child face enrollment | UNVERIFIED | real valid embedding persisted; invalid/liveness failure rejected |
| Child face-first login | UNVERIFIED | fresh camera/liveness + enrolled embedding match |
| Password/fallback login policy | UNVERIFIED | explicit allowed fallback + denial cases |
| Mandatory onboarding quiz | UNVERIFIED | gate before feed + persistence after completion |
| Recurring feed quiz | UNVERIFIED | interval trigger + destination restoration |
| Kids home/feed | UNVERIFIED | visible approved/allowed posts only |
| Stories | UNVERIFIED | viewer + allowed visibility + view tracking |
| Reels | UNVERIFIED | pagination/playback + parent control enforcement |
| Discover/search | UNVERIFIED | privacy/age/category enforcement |
| Own child profile | UNVERIFIED | profile + allowed posts |
| Other child profile | UNVERIFIED | relationship/privacy enforcement |
| Notifications | UNVERIFIED | delivery + mark-read |
| Create image post | UNVERIFIED | direct R2 upload through v2 flow |
| Create video/reel/story | UNVERIFIED | direct R2 upload + duration/sanitization checks |
| Coarse post location label | UNVERIFIED | text label only; no precise GPS storage |
| Async processing dispatch | UNVERIFIED | durable Modal-native enqueue + retry/redrive |
| AI ALLOWED path | UNVERIFIED | post promoted/sanitized and visible |
| AI REVIEW path | UNVERIFIED | remains private/quarantined |
| Parent REVIEW -> APPROVED | UNVERIFIED | authorized preview + byte promotion + feed visibility |
| Parent REVIEW -> BLOCKED | UNVERIFIED | quarantine deletion/invalidation + denial |
| Total AI failure | UNVERIFIED | fail-closed BLOCK |
| Partial AI failure | UNVERIFIED | REVIEW |
| R2 size/MIME mismatch | UNVERIFIED | completion rejected |
| Concurrent upload completion | UNVERIFIED | one post/job only |
| Worker spawn failure retry | UNVERIFIED | no stranded consumed upload |
| Stale processing redrive | UNVERIFIED | deterministic recovery |
| Image sanitization failure | UNVERIFIED | original bytes never published |
| Video sanitization failure | UNVERIFIED | original bytes never published |
| Author sees ALLOWED post in profile | UNVERIFIED | client refresh/query invalidation |
| Eligible follower sees ALLOWED post | UNVERIFIED | approved relationship + feed assertion |
| REVIEW/BLOCKED excluded from child feeds | UNVERIFIED | authorization + feed assertions |
| Like/unlike | UNVERIFIED | mutation + immediate UI state |
| Comment moderation | UNVERIFIED | allow/review/block behavior |
| Save/unsave | UNVERIFIED | mutation + saved list |
| Follow/request/approve/unfollow | UNVERIFIED | relationship lifecycle |
| Mute/block/report | UNVERIFIED | enforcement + UI |
| Conversation list | UNVERIFIED | approved-only relationships |
| Text chat | UNVERIFIED | send/read/pagination/moderation |
| Shared-post chat | UNVERIFIED | visibility + moderation |
| Media chat | UNVERIFIED | only if a fail-closed native moderated contract is implemented |
| Parent dashboard | PASS | Disposable PostgreSQL bearer journey returned the owned child summary and asserted its identity fields. |
| Parent safety queue | UNVERIFIED | ownership + preview authorization |
| Screen-time limit | UNVERIFIED | child lock enforcement |
| Quiet hours | UNVERIFIED | child lock enforcement |
| Feature controls | PASS | Disposable PostgreSQL journey disabled messaging, observed the Child route fail with `disabled_by_parent`, then restored it. Other switches remain covered by source/unit contracts, not a device run. |
| Category controls | UNVERIFIED | feed/post enforcement |
| Follow approvals | UNVERIFIED | parent authorization |
| Admin moderation | PASS | Disposable PostgreSQL journey covered queue, detail, ESCALATE, final APPROVE, two review rows, and dedicated admin audit output. |
| Fresh PostgreSQL bootstrap | PASS | Role E2E created an empty PostgreSQL 16 service and applied the schema plus production migration chain before testing. |
| Full backend suite | PASS | CI: 347 passed, 2 skipped, 0 failed/errors. |
| Route uniqueness | PASS | `tools/audit_all.py`: 130 routes discovered and no duplicate Android root or mobile method/path registration failure. |
| React Native unit/component suite | PASS | CI: 77 passed, 0 failed/skipped/cancelled across 19 suites. |
| React Native typecheck | PASS | CI `npm run typecheck` completed successfully. |
| Android Expo export | PASS | CI bundled 965 modules and exported `mobile_app/dist`. This is not an APK/device run. |
| Android critical E2E | UNVERIFIED | device/emulator journey evidence |
| R2 isolated object round-trip | PASS | Submission-readiness prefix upload, HEAD, GET, and DELETE completed with cleanup. |
| R2 full synthetic media lifecycle | PASS | Signed upload to quarantine, private REVIEW delivery, ALLOW sanitization/promotion/readback, BLOCK cleanup, and test-object cleanup passed with synthetic media. |
| Modal workspace/app/volume access | PASS | Authenticated `netlittle2` inspection found `littlenet-web`, `littlenet-ai`, `littlenet-uploads`, and `littlenet-model-cache`. |
| Modal AI readiness/authentication | FAIL | Bounded `/healthz` probe was not ready and the synthetic image moderation request returned HTTP 401; no secrets were printed or changed. |
| Modal idle cost guard | PASS | Active-container list was empty after the bounded probe and idle wait. |
| Real Resend inbox OTP | FAIL | `E2E_TEST_EMAIL` is present and a live registration was attempted, but the backend returned `email_sent=false`; no OTP verification evidence exists. |
| Moderation benchmark calibration | PASS | Six-row lawful synthetic calibration sample: exact-action agreement 0.666667, macro-F1 0.666667; ALLOW precision/recall 1.0/1.0, REVIEW 0.5/0.5, BLOCK 0.5/0.5. This is not production accuracy. |
| EAS authentication/project link | PASS | `eas-cli whoami --non-interactive` authenticated as `akshu1245`; the existing project `c4ce834d-fd50-4504-a311-820c3372b6dc` was linked without creating a project. |
| EAS preview APK build | PASS | Existing-project preview build `914dc2c5-740b-4f2e-aa2d-40e0ba0566e8` finished successfully for `com.littlenet.app`; artifact: https://expo.dev/artifacts/eas/Pak-g5Mj08VCdNHHiew-ZHgnSMDEHDzV2vNaqJ5w_FU.apk |
| Routine health does not wake GPU | UNVERIFIED | billing/container evidence |
| Final APK install/launch | UNVERIFIED | installed APK on Android device/emulator |

## Submission rule

LittleNet is not submission-ready while any critical journey above is `FAIL`, or while a required journey is `UNVERIFIED` without an explicitly documented limitation approved for the college demo.
