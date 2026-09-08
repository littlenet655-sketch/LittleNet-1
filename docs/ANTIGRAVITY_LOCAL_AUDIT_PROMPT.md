# Antigravity Prompt — LittleNet Local Pre-Rebuild Audit

Paste the content below into Antigravity from a clean local workspace.

---

You are acting as a senior software architect, backend engineer, PostgreSQL reviewer, AI-safety engineer, Flutter/Android engineer, security tester, and release engineer.

Repository:
`https://github.com/littlenet655-sketch/LittleNet-1`

Primary audit branch:
`feature/submission-rebuild-v2`

Stacked source branch for dataset work:
`feature/curated-dataset-v1`

This is a COLLEGE PROJECT, not a commercial production launch. Nevertheless, audit the code rigorously and report reality rather than claims.

## ABSOLUTE RULES

1. DO NOT deploy anything.
2. DO NOT upload media to Cloudflare R2.
3. DO NOT write to the live Neon/PostgreSQL database.
4. DO NOT invoke destructive Modal/Railway/Vercel/Cloudflare operations.
5. DO NOT merge PRs or push to `main`.
6. DO NOT invent missing assets, credentials, test results, routes, models, or features.
7. NEVER print or commit secrets. Mask any secret accidentally encountered.
8. Whisper/audio is intentionally retired. Do not reinstall Whisper, faster-whisper, story music, standalone audio upload, or voice upload. Verify that it stays retired.
9. Native Android must remain Flutter. Any active WebView dependency or WebView-based app shell is a P0 failure.
10. Child-visible unsafe/unknown media must fail closed.
11. Do not delete the old Flutter UI until a replacement V2 UI compiles and passes its tests. First audit and inventory it.

## PHASE 0 — GET AN EXACT LOCAL COPY

Clone/fetch the repository and check out exactly:

`feature/submission-rebuild-v2`

Record:
- branch name
- HEAD SHA
- git status
- Python version
- Flutter version
- Dart version
- Java/JDK version
- Android SDK version
- ffmpeg version
- OS

Fetch all refs so PR/base comparisons are possible, but do not merge anything.

Produce `audit/evidence/environment.txt`.

## PHASE 1 — INVENTORY EVERYTHING

Create a complete repository inventory grouped by:
- backend entrypoints
- Flask blueprints/routes
- auth
- parent
- child
- chat/messages
- posts/reels/stories
- quiz/learning
- admin/moderator
- database/schema/migrations
- services
- AI provider/client modules
- safety modules
- R2/object storage
- Modal deployment
- Railway/Vercel legacy or active deployment files
- Flutter source
- Android runner/build files
- CI workflows
- tests
- tools/audits
- HTML/Jinja legacy browser UI
- static JS/CSS
- model files
- dataset ingestion files

Find dead modules, duplicate implementations, stale wrappers, contradictory routes, and legacy code still imported by active runtime.

Create:
`audit/reports/01_repository_inventory.md`

## PHASE 2 — DATASET BLOCKER FIRST

The intended dataset contract is:
- 206 total media rows
- 194 ALLOWED
- 12 BLOCKED benchmark items
- 127 VIDEO
- 79 IMAGE
- 122 reels
- 84 non-reels
- Family 74
- Animals 58
- Crafts 26
- Gardening 21
- Cooking 15
- blocked benchmark 12

Expected local bundle names:
- `LittleNet_Dataset_Part1_of_2.zip`
- `LittleNet_Dataset_Part2_of_2.zip`

If they are not in the repository, search the current local workspace/Downloads only. If they cannot be found, report the exact missing paths and continue the code audit without fabricating dataset results.

Known blocker:
- CSV row 34, Animals: `fun-animal-facts-for-kids.jpg`
- CSV row 120, Gardening: `fun-animal-facts-for-kids.jpg`
- current payloads are byte-identical
- SHA-256: `e9821bdd4fd24a00abf2965d542287e7b969704501f1323acb10b62e9672dd56`
- row 120 metadata says `Garden Friends: Earthworms at Work`
- the current duplicated image is an animal-facts infographic, not an earthworm/gardening image

FIX RULE:
- First search the supplied local dataset/source folders for the genuine intended earthworm/gardening image.
- If a genuine matching source asset exists, replace ONLY `Member3Gardening/fun-animal-facts-for-kids.jpg` in the local corrected bundle/worktree, preserving the 206-row contract, then update the CSV file size/dimensions/hash-derived evidence if required.
- Do NOT generate a fake earthworm image and call it original source data.
- Do NOT silently relabel the duplicate animal image as gardening.
- If the correct source image does not exist, leave this as a P0 DATASET BLOCKER and report it.

After any legitimate replacement run full mechanical validation:
- exact 206/206 paths
- no missing/extra files
- SHA-256 duplicate scan across all 206 payloads
- CSV file size match
- media type/extension match
- image/video width + height match
- video duration tolerance
- readable/corrupt check
- CSV 24-column contract
- exact label/category counts

Then execute the ingestion tool in DRY-RUN ONLY. Never use `--execute` or `--publish` during this audit.

Create:
`audit/reports/02_dataset_validation.md`

## PHASE 3 — PYTHON SOURCE + TEST AUDIT

Inspect every active `.py` module and import graph.

Whisper rule:
- `safety/audio_service.py` is a retired compatibility shim only.
- Verify no active route reaches Whisper/audio inference.
- Verify requirements and Modal runtime contain no Whisper/faster-whisper model dependency.
- Exclude retired audio functionality from feature-completeness requirements, but still verify it cannot accidentally reactivate.

Run at minimum:
- Python compile/AST parse over every `.py`
- `python tools/audit_all.py`
- `python tools/audit_dynamic_sql.py`
- `python tools/audit_routes.py`
- `python tools/audit_templates.py`
- `python tools/readiness.py --source-only`
- `python tools/scope_check.py`
- full `pytest` suite
- Bandit using the same exclusions/settings as CI
- pip-audit against `requirements-core.txt`
- secret scan if gitleaks is installed

Do not stop at green tests. Read implementation code and find untested failure modes.

Create:
`audit/reports/03_python_and_ci.md`

## PHASE 4 — AUTHENTICATION / AUTHORIZATION

Trace every auth flow end-to-end.

Verify reality for:
- Parent registration
- Resend/email OTP delivery
- OTP hashing, expiry, retry limits and replay protection
- parent liveness/adult verification
- child creation only by verified parent
- child age capture
- face enrollment
- face login/liveness
- mandatory onboarding quiz
- bearer-token native mobile login/session restore/logout
- admin/moderator authentication
- suspended/revoked account behavior
- role authorization
- parent-child ownership/BOLA/IDOR protections
- object-level media authorization

If SMS authentication is not actually implemented, report `SMS NOT IMPLEMENTED`; do not turn email OTP into an SMS claim.

If the phrase “certificate authentication” appears in requirements/docs, determine whether it means TLS certificate validation, certificate pinning, or something else. Report actual implementation. Do not invent certificate auth.

Create an auth state diagram and endpoint ledger with roles, inputs, outputs, errors, DB mutations and tests.

Create:
`audit/reports/04_auth_authorization.md`

## PHASE 5 — DATABASE / NEON

Audit:
- `database/schema.sql`
- every migration in `db/migrations/`
- migration ordering/idempotency
- foreign keys
- uniqueness
- check constraints
- transaction boundaries
- row locks
- optimistic locking/state machines where present
- indexes and pagination support
- audit/event tables
- orphan cleanup
- deletion cascades
- SQL injection/dynamic identifiers
- connection pooling/preemption safety

Specifically inspect curated dataset tables:
- `content_categories`
- `curated_media_assets`
- `curated_content`
- hashtag tables
- `content_impressions`
- `feed_sessions`
- `feed_session_items`
- publication trigger/invariant

Prove a BLOCKED/REVIEW/PENDING asset cannot become child-visible through a DB bug.

Do not write to the live database. If a local/test Postgres is available, use an isolated temporary database.

Create:
`audit/reports/05_database.md`

## PHASE 6 — AI / CHILD SAFETY

Audit active modules including:
- `safety/moderation_service.py`
- `safety/policy.py`
- `safety/policy_config.py`
- `config/safety_policy.yaml`
- `safety/nsfw_policy.py`
- `safety/yolo_policy.py`
- `safety/visual_service.py`
- `safety/video_service.py`
- `safety/text_service.py`
- `safety/pii_service.py`
- `safety/presidio_adapter.py`
- `safety/document_service.py`
- `safety/face_service.py`
- `safety/scene_sampler.py`
- `safety/remote_client.py`
- `services/ai/**`
- `modal_ai.py`
- `ai_server.py`

Verify:
- AI timeout/error/malformed response semantics
- total failure fails closed
- partial failure cannot silently become ALLOW
- adult threshold 0.40 hard block contract
- dangerous/weapon block threshold 0.45 contract
- YAML is parsed/validated and cannot weaken safety by malformed configuration
- at least 80 configured dangerous/review object labels exist
- YAML labels are actually compared against detector output vocabulary
- high-confidence firearm/explosive/blade weapon paths BLOCK
- medium evidence REVIEWs where intended
- safe object does not trigger weapon block
- frame-sampled video cannot leak unsafe unsampled assumptions without documented limits
- text grooming/severe abuse/cyberbullying behavior
- PII/contact-sharing behavior
- documents do not bypass text/image moderation
- 12 restricted benchmark images never enter production media/catalog/feed

Important: distinguish CONFIGURED label coverage from MODEL-ACTUAL label coverage. A YAML list of 80+ strings is not proof the YOLO checkpoint can detect all 80+. Report both numbers separately.

Create:
`audit/reports/06_ai_safety.md`

## PHASE 7 — R2 / MEDIA LIFECYCLE

Audit Cloudflare R2 integration without touching live cloud data.

Verify:
- production bucket remains private
- signed URL TTL
- R2 key normalization
- account ID/full-endpoint normalization
- MIME handling
- upload-before-DB transaction pattern
- rollback/delete/outbox behavior
- orphan cleanup
- child access authorization before signed URL
- BLOCKED/REVIEW media never receives a child-accessible URL
- reels use fast-start MP4 delivery derivative
- video audio remains stripped per locked scope
- posters/thumbnails
- object deletion on account/post deletion

Create:
`audit/reports/07_media_r2.md`

## PHASE 8 — FEED / REELS / RECOMMENDATION

Audit social and curated content separately, then their intended merge.

Verify or mark missing:
- curated candidate generator
- child age gate
- parent category controls
- ALLOWED + safe gate BEFORE ranking
- recent-impression exclusion
- category balancing
- no >2 consecutive same-category items
- feed session stability
- cursor pagination
- no offset-only duplicate/skip issue for new V2 endpoint
- social + curated pool merge
- empty-social-graph fallback to curated safe content
- search/hashtags
- blocked item cannot appear through feed, reels, search, profile, saved, notification preview, share or direct media endpoint

Do not claim these are complete merely because their DB tables exist.

Create:
`audit/reports/08_feed_reels_recommendation.md`

## PHASE 9 — FLUTTER / ANDROID INVENTORY BEFORE REBUILD

Do NOT redesign yet. First document exactly what exists.

Inspect:
- `mobile_flutter/pubspec.yaml`
- `mobile_flutter/lib/main.dart`
- `mobile_flutter/lib/api.dart`
- `mobile_flutter/lib/widgets.dart`
- every `mobile_flutter/lib/screens/*.dart`
- tests
- `mobile_flutter/tool/prepare_android.sh`
- generated/native Android manifests and Gradle contracts

Inventory all existing pages/screens and API dependencies, including:
- splash/launch
- login
- parent signup
- OTP
- liveness
- child enrollment
- home
- feed
- reels
- post/create
- likes/comments
- chat/messages
- profile
- settings
- every nested settings/menu page
- notifications
- learning/quiz
- parent dashboard
- children
- controls
- screen time
- safety review
- admin/moderator queue/audit

Run:
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Android native-generation script in safe/local mode
- grep/import audit proving no WebView dependency

Do not delete old Flutter screen files during this audit.

Read `docs/FLUTTER_V2_REBUILD_CONTRACT.md` and produce a page-by-page replacement matrix:
OLD FILE/SCREEN -> API CONTRACT -> V2 SCREEN TO BUILD -> DELETE OLD WHEN.

Create:
`audit/reports/09_flutter_inventory.md`

## PHASE 10 — WEB / LEGACY UI

Inventory all Flask/Jinja templates and JS/CSS.

Determine which are:
- still required for browser admin/operator flows
- still referenced by tests/routes
- historical/dead
- duplicated by Flutter

Do not mass-delete server templates merely because the Android app is Flutter. Mark safe removal candidates with evidence.

Create:
`audit/reports/10_legacy_web_ui.md`

## PHASE 11 — DEPLOYMENT FILES, BUT NO DEPLOYMENT

Audit:
- Modal web/AI configs
- R2 secret names (names only, never values)
- Resend config
- Neon env-variable contracts
- Vercel/Railway files and whether they are current or legacy
- GitHub Actions
- health/readiness endpoints
- native APK workflows
- package/release scripts
- TLS-only backend requirements

Compare deployment docs to actual code and mark stale documentation.

Create:
`audit/reports/11_deployment.md`

## PHASE 12 — COMPLETE SECURITY REVIEW

Check:
- secrets
- CSRF for browser writes
- bearer token handling
- secure storage in Flutter
- password hashing
- OTP replay/bruteforce
- IDOR/BOLA
- SQL injection
- upload validation
- zip-slip/path traversal
- SSRF
- unsafe deserialization
- template XSS
- stored XSS from captions/usernames/comments
- authorization of signed media
- rate limiting
- audit log tampering
- fail-open paths
- race conditions / double moderator action
- screen-time bypass
- revoked-user cached data
- deleted-media stale URLs
- WebView absence
- cleartext HTTP disabled

Create:
`audit/reports/12_security.md`

## PHASE 13 — CLAIM VS REALITY

Make one table with columns:
FEATURE | IMPLEMENTED | TESTED | LIVE-PROVEN | PARTIAL/MISSING | FILE EVIDENCE | SAFE TO CLAIM IN COLLEGE DEMO

Include every major feature and explicitly include:
- Parent/Child accounts
- email OTP
- SMS (likely absent unless proven)
- face login
- liveness
- adult verification
- moderation
- NSFW
- weapons/YOLO
- 80+ YAML policy vocabulary
- PII
- grooming
- cyberbullying
- posts
- stories
- reels
- chat
- screen time
- parent review
- admin/moderator
- recommendations
- curated 206-item dataset
- R2
- Neon
- Flutter APK
- no-WebView
- offline support
- notifications
- Whisper/audio retirement

Create:
`audit/reports/13_claim_vs_reality.md`

## PHASE 14 — FINAL OUTPUT

Do not modify production resources.

Create:
- `audit/ANTIGRAVITY_MASTER_AUDIT.md`
- `audit/ANTIGRAVITY_FINDINGS.json`
- `audit/ANTIGRAVITY_COMMAND_LOG.txt`

The master audit must start with:

### VERDICT
One of:
- READY_FOR_V2_REBUILD
- NOT_READY_FOR_V2_REBUILD

Then include:
- P0 blockers
- P1 blockers
- P2 improvements
- exact failing commands/tests
- exact file:line evidence
- dataset status
- backend status
- database status
- safety status
- Flutter status
- cloud/deployment-contract status
- what is safe to delete
- what must not be deleted
- precise next build order

Do NOT say “everything is perfect” unless every applicable command is green and every known blocker is either fixed with evidence or explicitly outside scope.

Finally print a concise terminal summary and STOP. Do not deploy, publish, merge, or delete the working UI.

---
