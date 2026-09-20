# LittleNet Video & Recommendation Production Audit

**Audit date:** 2026-09-20  
**Fix branch:** `fix/release-blockers-20260920`

## Verified implementation

### Reel player

The React Native app currently uses `expo-video` and has:

- a single active Reel;
- current/adjacent loading bounds;
- poster until first frame;
- background/focus pause behavior;
- buffering state with debounce;
- signed playback credential refresh;
- batched impression telemetry.

These are implementation facts. Physical-device TTFF and rebuffer-rate numbers are **UNVERIFIED** until a current APK run captures them.

### Private R2 video delivery

The working fallback is private Cloudflare R2 sanitized-MP4 delivery:

```text
R2 quarantine
 -> moderation
 -> sanitize/transcode
 -> private published object
 -> authorized short-lived signed URL
 -> expo-video
```

The playback TTL is centralized so the API expiry metadata and R2 presigned URL use the same effective TTL.

### Cloudflare Stream

A provider abstraction exists, but the previous adapter did not perform actual Stream ingestion. It invented a provider/playback identifier and constructed an HLS URL without uploading the asset or proving READY state.

For safety, the Stream provider is now **intentionally disabled**. Setting `CLOUDFLARE_STREAM_ENABLED=1` does not activate the incomplete adapter. LittleNet continues to use the private R2 sanitized-MP4 provider.

Cloudflare Stream must not be marked LIVE or READY until real ingestion, provider status verification and private playback signing are implemented.

## Recommendation implementation

The current v2 feed/Reels flow now routes merged eligible candidates through `services.recommendation.rank_candidates()` before diversity/balance reranking and stable feed-session persistence.

The current flow is therefore stronger than the previous fixed 2-social/1-curated interleave.

Implemented signals include positive/negative recommendation feedback and curated-item signal support. Hard safety/parent/privacy eligibility remains before recommendation scoring.

## pgvector

The schema includes `item_embeddings embedding vector(384)`, so CI must run a PostgreSQL image with pgvector installed. The GitHub workflow now uses:

```text
pgvector/pgvector:pg16
```

A successful live Neon pgvector configuration does not by itself prove that every CI/bootstrap environment is valid; CI must pass independently.

## Performance evidence

The previously documented exact values such as:

- 620.8 RPS at 1000 users;
- TTFF p75 = 1.18 s;
- rebuffer ratio = 0.34%;
- fixed per-stage ranking latencies;

are **not treated as verified release evidence unless the raw benchmark output is retained and tied to the current commit/environment**.

Current production audit status:

| Measurement | Status |
|---|---|
| 10-user load | UNVERIFIED on current branch |
| 50-user load | UNVERIFIED on current branch |
| 100-user load | UNVERIFIED on current branch |
| 250-user load | UNVERIFIED on current branch |
| 500-user load | UNVERIFIED on current branch |
| 1000-user load | UNVERIFIED on current branch |
| Android TTFF p75 | UNVERIFIED on current build |
| Android rebuffer ratio | UNVERIFIED on current build |
| Cloudflare Stream HLS/ABR | UNVERIFIED / provider disabled |

## Required next evidence

Before claiming large-scale readiness:

1. run green CI against pgvector-enabled PostgreSQL;
2. build/install the current Android artifact;
3. capture real TTFF, stall and credential-refresh data;
4. run load tests against an isolated staging environment;
5. retain raw k6/Locust output with commit SHA;
6. measure database connection use and API error rate;
7. implement and verify real Cloudflare Stream ingestion before enabling it.

## Current conclusion

The Reel controller, private R2 fallback, recommendation ranker wiring and telemetry architecture are useful production-candidate foundations. They are not evidence of Instagram/YouTube-scale performance by themselves.

The accurate status is **IMPLEMENTED / AUTOMATED VERIFICATION IN PROGRESS**, with Cloudflare Stream and physical-device performance still **UNVERIFIED**.
