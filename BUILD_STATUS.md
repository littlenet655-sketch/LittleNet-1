# LittleNet Build Status

_Last verified: 2026-09-07_

## Repository/source status

The current `main` branch is source-clean and submission-packaging-ready. The release pipeline is intentionally fail-closed: a live APK is produced only after the real web deployment, database, AI service and external dependencies pass their release gates.

### Verified on GitHub CI

- Python/source audit: PASS
- LittleNet regression suite: PASS
- parameterized/dynamic SQL audit: PASS
- MediaPipe pinned-asset verification: PASS
- Gitleaks secret scan: PASS
- `pip-audit` dependency scan: PASS
- Bandit application scan: PASS
- clean submission ZIP packaging: PASS

Exact test/route counts change as the project is hardened; GitHub Actions is the canonical current evidence instead of old fixed counts.

## Locked release chain

`.github/workflows/deploy-modal.yml` enforces this order:

1. validate the public HTTPS LittleNet URL and Modal credentials
2. deploy the protected Modal AI service
3. warm every locked-scope model/dependency
4. deploy the Flask/Jinja web service
5. initialize/apply PostgreSQL migrations
6. seed the compulsory age-banded quiz bank
7. run DB/schema + AI + Presidio + MediaPipe liveness + mail + R2 + `BASE_URL` preflight
8. require public `/healthz` and strict `/readyz` = `ready`
9. run Playwright release smoke tests against the public URL
10. only then build an Android APK injected with that same verified live URL

## APK status

The old repository binary `LittleNet-v1.0-submission.apk` was retired because it embedded a placeholder backend URL and could be mistaken for a final build. APK files are excluded from the source submission ZIP and ignored by Git.

The canonical final APK is the GitHub Actions artifact named **`LittleNet-live-verified-apk`**, generated only after the live release job succeeds. Do not submit an APK copied from the repository source tree.

## Current proven external blocker

The first connected live-release run on 2026-09-07 stopped at credential validation because these GitHub Actions repository secrets are not configured:

- `MODAL_TOKEN_ID`
- `MODAL_TOKEN_SECRET`

Because authentication failed before deployment, AI deploy, web deploy, DB migration, live smoke testing and live APK generation were correctly skipped. This is an account-level configuration task; it cannot be solved by committing source code.

## External configuration the next successful live run will verify

After the two Modal GitHub secrets exist, the workflow will expose any remaining runtime configuration issue precisely. The Modal `littlenet-web-secrets` secret must ultimately contain working values for the PostgreSQL database, Flask secret, protected AI service, public `BASE_URL`, SMTP/mail and Cloudflare R2 dependencies.

## Guardian verification hardening

The production guardian path is Express Guardian Verification with a live camera plus server-side anti-spoof/adult verification. The legacy deterministic Aadhaar mock is blocked on public deployments and can only be enabled explicitly on local HTTP localhost/127.0.0.1 development. Missing/malformed adult-verification output fails closed. Legacy token-only child activation is disabled.

## Status summary

- **Source/CI ready:** YES
- **Clean source submission ZIP:** YES
- **Live Modal deployment verified:** NO — blocked by missing GitHub Modal credentials
- **Production/live-backed APK ready:** NO — generated only after live release passes
