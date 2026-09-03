# LittleNet Build Status

## Local source status
The existing LittleNet repository now covers the corrected project PPT/report plus the final agreed additions without changing the Flask/Jinja/PostgreSQL architecture. No Git metadata is present in this working tree.

### Current verified source evidence
- **122/122 tests passing**
- **110 Flask routes / 0 route-audit errors**
- **64 templates / 0 template-audit errors**
- **41/41 scope checks passing**
- Python compile clean
- JavaScript syntax clean
- Android XML clean
- CSP/template safety audit clean
- No Git metadata

### Newly closed gaps
- Server-enforced Parent Mode quiet hours with timezone support
- Real child online/offline presence on Parent Home
- Parent Home 7-day behavior and quiz activity metrics
- Feed/Clips direct visibility and social interactions limited to approved relationships
- Discover changed from global/random children to approved-network / same-school / same-parent suggestions
- BLOCK/REVIEW in-app alerts plus best-effort SMTP email safety alerts
- Explicit Admin post-removal action with audit logging
- Parent/Admin review UI, model-signal bars and blurred REVIEW preview
- Expanded quiz seed and Learn card
- AI adapter timeouts and normalized max-score ensemble

## Locked safety invariant
Adult/sexual evidence >= 0.40 and weapon evidence >= 0.45 hard-block before ordinary risk thresholds. Total safety outage cannot ALLOW content. Partial safety failure without hard-block evidence goes to REVIEW. Kids Mode queries expose only content that has passed the required relationship, Parent Control, age/category and safety checks.

## Deployment source ready
- `Dockerfile.web` — lightweight Flask/Jinja web service
- `Dockerfile.ai` / `ai_server.py` — heavyweight AI service
- `modal_ai.py` — optional Modal GPU deployment
- PostgreSQL schema + idempotent upgrade
- `/healthz` and `/readyz`
- GitHub CI and APK build workflow
- Android WebView source

## Remaining external blockers
1. Real PostgreSQL host and production `DATABASE_URL`.
2. Real HTTPS LittleNet backend URL.
3. Real execution/model warm-up for NudeNet, Falconsai, CLIP, YOLO, Detoxify, Whisper and DeepFace.
4. End-to-end tests using real safe/adult/weapon/video/audio/face samples.
5. Android SDK/Gradle execution (or GitHub Actions) to generate the APK after the HTTPS URL exists.
6. Physical Android camera/mic/Face Login/Live Safety test.

`SOURCE_READY=True`; `APK_BINARY_READY=False` until those external runtime steps are completed.
