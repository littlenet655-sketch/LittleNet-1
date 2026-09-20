# LittleNet Production Readiness Assessment

**Assessment date:** 2026-09-20  
**Fix branch:** `fix/release-blockers-20260920`  
**Classification:** **PRODUCTION CANDIDATE — VERIFICATION PENDING**

This document uses evidence states consistently:

- **IMPLEMENTED** — source exists.
- **AUTOMATED_TESTED** — covered by automated tests.
- **LIVE_SERVICE_VERIFIED** — exercised against the configured live service.
- **DEVICE_VERIFIED** — exercised on a physical Android device with the current build.
- **UNVERIFIED** — no current evidence is available.

A source implementation is not treated as live or device verification.

## Critical release gates

| Gate | Current state | Evidence / blocker |
|---|---|---|
| Clean PostgreSQL bootstrap | **PENDING CI** | CI now uses `pgvector/pgvector:pg16`; must pass on PR/main before release. |
| Backend regression suite | **PENDING CI** | Must pass after the pgvector and webhook changes. |
| Python security scan | **PENDING CI** | Expo push delivery no longer uses `urllib.request.urlopen`; Bandit must confirm. |
| Secret scan | **AUTOMATED_TESTED** | Existing Gitleaks job passed on the previous main commit; rerun required for this branch. |
| Mobile TypeScript | **PENDING CI** | Previously passed; rerun required after OTP delivery-status UI changes. |
| Mobile tests | **PENDING CI** | Previously 83/83; rerun required after current changes. |
| Expo dependency alignment | **IMPLEMENTED** | `expo ~57.0.24`, `expo-image-picker ~57.0.19`; `expo install --check` must pass. |
| Android export | **PENDING CI** | Previous export passed; current branch must be rebuilt. |
| Production OTP secrecy | **IMPLEMENTED** | Production cannot expose/print `dev_code`; development OTP now requires explicit non-production opt-in. |
| Resend acceptance vs delivery | **IMPLEMENTED** | Provider acceptance is recorded separately; verified webhook records delivered/bounced/suppressed/failed states. |
| Resend webhook | **IMPLEMENTED / LIVE UNVERIFIED** | Requires `RESEND_WEBHOOK_SECRET` and a live Resend webhook configuration pointing to `/webhooks/resend`. |
| Direct R2 media pipeline | **IMPLEMENTED** | Private sanitized MP4 remains the authoritative production fallback. |
| Cloudflare Stream | **DISABLED / UNVERIFIED** | Adapter is intentionally fail-closed because real Stream ingestion, readiness confirmation, and private token minting are not yet implemented. |
| Recommendation ranker wiring | **IMPLEMENTED** | Current feed-session creation calls `rank_candidates()`; current CI/load evidence still required. |
| Physical guardian camera | **UNVERIFIED** | Must be tested with current APK on Android hardware. |
| Physical child face enrollment/login | **UNVERIFIED** | Must be tested with current APK and live AI service. |
| Physical Reel playback | **UNVERIFIED** | Must be tested on current APK with real network transitions. |
| Push delivery to device | **UNVERIFIED** | Requires a current Expo push token and physical device. |

## OTP security contract

Production must satisfy all of the following:

1. `ENABLE_DEV_OTP` is absent or `0`.
2. The registration/resend APIs never return `dev_code` in production.
3. OTP values are not printed to production logs.
4. A Resend HTTP 200/201 is treated as provider acceptance, not proof of mailbox delivery.
5. Resend webhook events update the delivery lifecycle.
6. Bounced/suppressed addresses are surfaced to the OTP screen.
7. Hard-bounced addresses are not automatically unsuppressed.

## Video delivery contract

The verified production fallback remains:

```text
mobile
  -> signed private R2 quarantine upload
  -> moderation
  -> sanitized H.264 MP4 + poster
  -> private published R2 object
  -> short-lived authorized signed playback URL
  -> expo-video
```

Cloudflare Stream is **not** considered implemented merely because a provider class exists. It remains disabled until all of these are implemented and verified:

- real Stream API ingestion;
- real provider UID persistence;
- PROCESSING -> READY status from provider evidence;
- signed/private playback credentials;
- webhook or reliable status polling;
- deletion/retry behavior;
- Android HLS/ABR device verification.

## Final release requirement

LittleNet may be called **PRODUCTION READY** only after the current commit has:

1. green backend, security, secret-scan and mobile CI;
2. clean schema/migration bootstrap;
3. live Resend webhook configuration and one delivered + one controlled failure verification;
4. real OTP flow without `dev_code`;
5. current APK installation on physical Android;
6. guardian camera, child face, upload/moderation and Reel playback device journeys;
7. REVIEW/BLOCK non-leakage verification;
8. current evidence recorded with commit SHA and device/build identifiers.

Until those gates are complete, the correct classification is **PRODUCTION CANDIDATE — VERIFICATION PENDING**.
