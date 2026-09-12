from __future__ import annotations

import json
import re
import shutil
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def write(rel: str, content: str) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")


def remove(rel: str) -> None:
    path = ROOT / rel
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def replace_once(rel: str, old: str, new: str) -> None:
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one match in {rel}, found {count}: {old!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Remove the retired native clients and their release workflows.
for rel in (
    "mobile_flutter",
    "android",
    ".github/workflows/flutter-native.yml",
    ".github/workflows/release-android.yml",
):
    remove(rel)

# Fix the mobile API identity without touching the API contract itself.
replace_once(
    "mobile/api.py",
    'return jsonify(ok=True, client="flutter", webview=False, api_version=1)',
    'return jsonify(ok=True, client="react-native", framework="expo", webview=False, api_versions=[1, 2])',
)

# Wire the existing scene-aware sampler into real video moderation.
replace_once(
    "safety/visual_service.py",
    "from .common import env_flag,normalize_signals,timed_call,timeout_seconds\n",
    "from .common import env_flag,normalize_signals,timed_call,timeout_seconds\nfrom .scene_sampler import combined_frame_indices\n",
)
replace_once(
    "safety/visual_service.py",
    "    idxs=[int(i*max(total-1,0)/max(max_frames-1,1)) for i in range(min(max_frames,max(total,1)))];outs=[]\n",
    "    idxs=combined_frame_indices(path,total,max_frames);outs=[]\n",
)
replace_once(
    "safety/visual_service.py",
    "        out['model_signals']={'sampled_frames':len(outs),'requested_frames':requested,'frames':[x.get('model_signals',{}) for x in outs]}\n",
    "        out['model_signals']={'sampled_frames':len(outs),'requested_frames':requested,'sampling':'scene+uniform','frames':[x.get('model_signals',{}) for x in outs]}\n",
)

write(
    ".gitignore",
    r'''
__pycache__/
*.py[cod]
.pytest_cache/
.env
.env.*
!.env.example
.venv/
venv/
uploads/
/models/
model_cache/
*.log
.DS_Store
.vscode/
.idea/
*.jks
*.keystore
*.apk
*.aab
*.db
*.sqlite
*.sqlite3
*.zip
scratch/
.neon
node_modules/
mobile_app/.expo/
mobile_app/dist/
mobile_app/.env
mobile_app/.env.*
!mobile_app/.env.example
coverage/
playwright-report/
test-results/
datasets/*.csv
datasets/Member_2_Processed_Dataset/
static/vendor/
recovery_backup/
tools/k6/
.project
.classpath
.settings/
.agent/
.agents/
agent/
.claude/
.cursor/
.mcp.json
.codex/
walkthrough.md
ngrok.exe
''',
)

write(
    "AGENTS.md",
    r'''
# LittleNet Agent Contract

## Goal
LittleNet is a child-safe social and learning application. Preserve the working Python backend and build the mobile client in `mobile_app/` only.

## Source of truth
- Mobile: React Native + Expo + TypeScript in `mobile_app/`.
- Backend/API: existing Flask/Python modules. Do not rewrite the backend into another framework.
- Database: PostgreSQL/Neon through the existing `database/` layer.
- AI/moderation: existing `safety/`, `services/`, `modal_ai.py`, and async media worker paths.
- Media: private R2 storage. New mobile image/video posting must use `/api/mobile/v2/uploads/*` and processing status APIs.

## Non-negotiable rules
1. Do not create a second mobile app root.
2. Do not generate a WebView wrapper.
3. Do not move business rules into the client. Parent controls, moderation, screen time, relationship approval and safety remain server-enforced.
4. Do not replace working backend modules unless a concrete bug requires it.
5. Never put backend secrets in Expo. The only expected mobile environment variable is `EXPO_PUBLIC_API_BASE_URL` unless a new public value is explicitly required.
6. Prefer `/api/mobile/v2` where a v2 route exists. Keep v1 only for endpoints that have no v2 equivalent.
7. Direct media upload goes to R2 quarantine, then background moderation, then status polling. Do not reintroduce synchronous upload-through-AI behavior.
8. Keep package identity `com.littlenet.app`.
9. Before finishing a change, run `npm run typecheck` and `npm run export:android` in `mobile_app/`, plus the relevant Python tests for backend changes.

## UI direction
Use the provided LittleNet/Stitch visual references when they exist, with a polished Instagram-familiar layout adapted for children. Reuse a small set of shared primitives and tokens; do not add multiple UI systems.

## Definition of done
A changed user path is wired to the real API, has loading/error/empty states, passes type checking, and does not weaken server-side safety controls.
''',
)

write(
    "STACK.md",
    r'''
# LittleNet Locked Stack

## Mobile
- React Native 0.86.x
- Expo SDK 57
- React 19.2.x
- TypeScript
- App root: `mobile_app/`
- Android package: `com.littlenet.app`
- Mobile configuration: `EXPO_PUBLIC_API_BASE_URL` only for the public backend URL

## Backend
- Python 3.11
- Flask application already present in this repository
- PostgreSQL / Neon
- Cloudflare R2 private media storage
- Modal for AI workloads
- QStash for production asynchronous media-processing dispatch

## Safety architecture
- Text/PII checks remain server-side.
- Image/video moderation remains server-side.
- Existing scene-aware frame sampling augments uniform video sampling.
- Parent review and moderator decisions remain auditable server-side state.
- New media uses direct R2 quarantine upload plus asynchronous processing.

## Engineering rules
- One mobile root only: `mobile_app/`.
- No WebView application shell.
- No second backend framework.
- No client-side copy of safety or parent-control authority.
- No backend secrets in mobile environment files.
- Prefer existing APIs/services over new parallel implementations.
''',
)

write(
    "README.md",
    r'''
# LittleNet — Child-Safe Social & Learning Platform

LittleNet is a college major project for children aged 6–16. It combines a familiar social experience with parent-owned controls, age-banded learning breaks, approved-only interaction and server-side AI content safety.

## Canonical architecture

```text
React Native / Expo mobile app (`mobile_app/`)
                 |
                 | HTTPS + bearer auth
                 v
        Flask mobile APIs (v1 + v2)
                 |
      +----------+-----------+
      |                      |
PostgreSQL / Neon      Private R2 media
      |                      |
      +------ async ----------+
             QStash -> Modal AI
                    |
             Parent/Admin review
```

The Python backend is the authority for moderation, parent controls, screen time, quiet hours, relationship approval, safety review and media publication state.

## Mobile client

The only mobile application root is `mobile_app/`.

```bash
cd mobile_app
cp .env.example .env
npm install
npm run typecheck
npm run start
```

Set:

```text
EXPO_PUBLIC_API_BASE_URL=https://YOUR-LITTLENET-BACKEND
```

Do not put database, R2, mail, AI or queue secrets in the mobile environment.

### Mobile API rules

- Authentication and remaining legacy-compatible endpoints: `/api/mobile/v1/*`
- Feed/reels/discover and direct media workflow: `/api/mobile/v2/*`
- New image/video upload flow:
  1. `POST /api/mobile/v2/uploads/session`
  2. upload directly to the returned R2 URL
  3. `POST /api/mobile/v2/uploads/<upload_id>/complete`
  4. poll `GET /api/mobile/v2/posts/<post_id>/processing-status`
  5. publish only after server-side moderation reaches an allowed state

## Backend development

```bash
python -m venv venv
# Windows: venv\Scripts\activate
# Linux/macOS: source venv/bin/activate
pip install -r requirements-core.txt
python tools/init_db.py
python app.py
```

Use `.env.example` as the backend configuration reference.

## Important directories

```text
mobile_app/       React Native / Expo / TypeScript client
mobile/           Bearer-auth mobile API
admin/            Admin/moderator services and web routes
auth/             Authentication and verification
child/            Child feed/discovery/profile logic
childMessage/     Approved-only messaging
parent/           Parent dashboard and controls
quiz/             Learning and quiz gates
safety/           AI safety, face and moderation services
services/         Media, controls, usage, queue and shared services
database/         PostgreSQL schema and migrations
uploadPost/       Existing post/reel/story web pipeline
```

## Validation

Backend/source checks:

```bash
python tools/audit_all.py
python tools/scope_check.py
python tools/readiness.py --source-only
```

Mobile checks:

```bash
cd mobile_app
npm install
npm run typecheck
npm run export:android
```

GitHub Actions contains separate backend/security and React Native validation workflows. A manual mobile release workflow is included for EAS once the repository variables/secrets for the Expo project are configured.

## Safety principles

- Fail closed when safety evidence is unavailable.
- Keep parent controls server-enforced.
- Keep child media private until approved.
- Require approved relationships for restricted interaction.
- Never embed production credentials in the mobile client.
''',
)

write(
    "REPLIT.md",
    r'''
# Replit Handoff

Replit should continue from the existing architecture, not redesign it.

## Work here
`mobile_app/` is the only mobile frontend. Build screens, navigation and interactions there.

## Preserve these systems
Do not rewrite `mobile/`, `auth/`, `child/`, `parent/`, `admin/`, `quiz/`, `safety/`, `services/`, `database/`, `modal_ai.py` or `modal_web.py` unless fixing a demonstrated backend defect.

## API preference
Use v2 for feed/reels/discover and all new media upload/processing flows. Use v1 only where no v2 endpoint exists.

## Media posting
Never send a large image/video through the synchronous AI request path from the phone. Request an upload session, upload directly to R2 quarantine, complete the session, then show processing state while the background worker moderates it.

## Secrets
Mobile code may receive `EXPO_PUBLIC_API_BASE_URL`. Backend secrets stay backend-only.

## Before changing backend code
Search for an existing service/route first. LittleNet already has async jobs, R2 storage, moderation, parent controls, usage limits, face flows, messaging and mobile APIs.

## Required checks
```bash
cd mobile_app
npm install
npm run typecheck
npm run export:android
cd ..
python tools/audit_all.py
```
''',
)

write(
    "BUILD_STATUS.md",
    r'''
# LittleNet Build Status

_Last migration preparation: 2026-09-12_

## Repository state
- Python backend retained as the working server authority.
- React Native / Expo / TypeScript is the sole mobile source in `mobile_app/`.
- Duplicate native Android scaffolding is removed from source control.
- Mobile package manifests are tracked by Git.
- CI no longer depends on the retired client toolchain.
- Direct R2 + asynchronous moderation remains the required mobile media flow.
- Scene-aware video frame selection is wired into the active visual moderation path.

## Validation gates
- `python tools/audit_all.py`
- `python tools/scope_check.py`
- `python tools/readiness.py --source-only`
- `cd mobile_app && npm install && npm run typecheck && npm run export:android`

Cloud credentials and final EAS/Modal releases remain external deployment configuration, not source-code readiness blockers.
''',
)

write(
    "SCOPE_STATUS.md",
    r'''
# LittleNet Scope Status

`python tools/scope_check.py` is the source-level guard for the locked college scope.

The scope includes Kids/Parent/Admin modes; feed/posts/reels/stories/chat; approved social interaction; discover; text/PII and visual safety; parent review; screen time and quiet hours; alerts; personalization; quizzes/learning; face/liveness flows; private R2 media; PostgreSQL audit data; React Native mobile source; and Modal AI deployment.

Standalone audio/voice moderation is outside the locked runtime. Video safety is based on visual evidence and scene-aware plus time-distributed frame sampling.

The source check does not claim that external cloud credentials or a store release are configured.
''',
)

write(
    ".env.example",
    r'''
SECRET_KEY=replace-with-a-long-random-secret
DATABASE_URL=postgresql://user:password@host:5432/littlenet?sslmode=require
BASE_URL=https://your-littlenet-web.example
COOKIE_SECURE=1
MAIL_EMAIL=
MAIL_PASSWORD=
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_USE_TLS=true
AI_SERVICE_URL=https://your-littlenet-ai.example
AI_SHARED_SECRET=replace-with-another-long-random-secret
AI_REQUEST_TIMEOUT=180
UPLOAD_FOLDER=/tmp/littlenet-uploads
MODEL_CACHE_DIR=/tmp/littlenet-models

# Cloudflare R2 private media storage
R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET=littlenet-media
R2_SIGNED_URL_TTL=300

# Async media processing. Production must use qstash.
JOB_QUEUE_PROVIDER=local
QSTASH_TOKEN=
QSTASH_MODAL_ENDPOINT=
QSTASH_URL=https://qstash.upstash.io
LITTLENET_SYNC_JOBS=0

# Cloudflare Turnstile
TURNSTILE_SITE_KEY=
TURNSTILE_SECRET_KEY=

# AI hardening
LITTLENET_MODEL_TIMEOUT_SECONDS=90
LITTLENET_VIDEO_FRAMES_TIMEOUT_SECONDS=240
LITTLENET_VIDEO_SAMPLE_INTERVAL_SECONDS=3
LITTLENET_VIDEO_MAX_FRAMES=60
LITTLENET_ENABLE_SCENEDETECT=1
LITTLENET_SCENEDETECT_THRESHOLD=27
LITTLENET_SCENEDETECT_MIN_FRAMES=12
LITTLENET_DETOXIFY_MODEL=multilingual
LITTLENET_DANGEROUS_OBJECTS=
LITTLENET_ENABLE_OPENNSFW2=0
LITTLENET_ENABLE_EXTRA_NSFW=0
LITTLENET_EXTRA_NSFW_MODEL=
LITTLENET_ENABLE_TEXT_CLASSIFIER=0
LITTLENET_TEXT_SAFETY_MODEL=

APP_TIMEZONE=Asia/Kolkata

K2_HORIZON_ENABLED=true
K2_HORIZON_BASE_URL=https://api.ifm.ai/v1
K2_HORIZON_API_KEY=
K2_HORIZON_MODEL=IFM/K2-Horizon-375B-A23B
K2_CONNECT_TIMEOUT=5
K2_READ_TIMEOUT=30
K2_MAX_RETRIES=2
K2_CIRCUIT_BREAKER_THRESHOLD=5
K2_CIRCUIT_BREAKER_RESET_SECONDS=60
''',
)

write(
    "mobile_app/package.json",
    r'''
{
  "name": "littlenet-mobile",
  "version": "1.0.0",
  "private": true,
  "main": "node_modules/expo/AppEntry.js",
  "scripts": {
    "start": "expo start",
    "android": "expo start --android",
    "ios": "expo start --ios",
    "typecheck": "tsc --noEmit",
    "export:android": "expo export --platform android --output-dir dist"
  },
  "dependencies": {
    "expo": "57.0.22",
    "react": "19.2.3",
    "react-native": "0.86.3"
  },
  "devDependencies": {
    "@types/react": "19.2.18",
    "typescript": "5.9.2"
  },
  "engines": {
    "node": ">=22.13.0"
  }
}
''',
)

write(
    "mobile_app/app.json",
    r'''
{
  "expo": {
    "name": "LittleNet",
    "slug": "littlenet",
    "version": "1.0.0",
    "orientation": "portrait",
    "scheme": "littlenet",
    "userInterfaceStyle": "light",
    "newArchEnabled": true,
    "android": {
      "package": "com.littlenet.app",
      "versionCode": 1
    },
    "ios": {
      "bundleIdentifier": "com.littlenet.app",
      "supportsTablet": true
    }
  }
}
''',
)

write(
    "mobile_app/eas.json",
    r'''
{
  "cli": {
    "version": ">= 16.0.0"
  },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal"
    },
    "preview": {
      "distribution": "internal",
      "android": {
        "buildType": "apk"
      }
    },
    "production": {
      "autoIncrement": true
    }
  }
}
''',
)

write(
    "mobile_app/tsconfig.json",
    r'''
{
  "extends": "expo/tsconfig.base",
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true
  },
  "include": ["**/*.ts", "**/*.tsx", ".expo/types/**/*.ts", "expo-env.d.ts"]
}
''',
)

write(
    "mobile_app/expo-env.d.ts",
    r'''
/// <reference types="expo/types" />
''',
)

write(
    "mobile_app/.env.example",
    r'''
EXPO_PUBLIC_API_BASE_URL=https://your-littlenet-backend.example
''',
)

write(
    "mobile_app/src/api/client.ts",
    r'''
export const API_BASE_URL = (process.env.EXPO_PUBLIC_API_BASE_URL ?? '').replace(/\/+$/, '');

export class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export const routes = {
  health: '/api/mobile/v1/health',
  login: '/api/mobile/v1/auth/login',
  feed: '/api/mobile/v2/kids/feed',
  reels: '/api/mobile/v2/kids/reels',
  discover: '/api/mobile/v2/kids/discover',
  uploadSession: '/api/mobile/v2/uploads/session',
  uploadComplete: (uploadId: string) => `/api/mobile/v2/uploads/${encodeURIComponent(uploadId)}/complete`,
  processingStatus: (postId: number) => `/api/mobile/v2/posts/${postId}/processing-status`,
} as const;

export async function apiRequest<T>(
  path: string,
  options: RequestInit = {},
  token?: string,
): Promise<T> {
  if (!API_BASE_URL) {
    throw new ApiError(0, 'EXPO_PUBLIC_API_BASE_URL is not configured');
  }
  const headers = new Headers(options.headers);
  headers.set('Accept', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  const response = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof payload?.error === 'string' ? payload.error : `Request failed (${response.status})`;
    throw new ApiError(response.status, message);
  }
  return payload as T;
}
''',
)

write(
    "mobile_app/App.tsx",
    r'''
import { useEffect, useState } from 'react';
import { SafeAreaView, StatusBar, StyleSheet, Text, View } from 'react-native';
import { API_BASE_URL, apiRequest, routes } from './src/api/client';

type Health = {
  ok: boolean;
  client?: string;
  framework?: string;
  api_versions?: number[];
};

export default function App() {
  const [status, setStatus] = useState(API_BASE_URL ? 'Checking backend…' : 'Set EXPO_PUBLIC_API_BASE_URL');

  useEffect(() => {
    if (!API_BASE_URL) return;
    let active = true;
    apiRequest<Health>(routes.health)
      .then((result) => active && setStatus(result.ok ? 'Backend connected' : 'Backend not ready'))
      .catch(() => active && setStatus('Backend unavailable'));
    return () => {
      active = false;
    };
  }, []);

  return (
    <SafeAreaView style={styles.page}>
      <StatusBar barStyle="dark-content" />
      <View style={styles.card}>
        <Text style={styles.brand}>LittleNet</Text>
        <Text style={styles.title}>React Native mobile foundation</Text>
        <Text style={styles.body}>{status}</Text>
        <Text style={styles.note}>Replit should build the real Kids, Parent and Admin screens from this single app root.</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: '#ffffff', justifyContent: 'center', padding: 24 },
  card: { borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 24, padding: 24, gap: 10 },
  brand: { fontSize: 28, fontWeight: '800' },
  title: { fontSize: 20, fontWeight: '700' },
  body: { fontSize: 16 },
  note: { fontSize: 14, lineHeight: 20 },
});
''',
)

write(
    "mobile_app/README.md",
    r'''
# LittleNet Mobile

This directory is the only mobile application root.

```bash
cp .env.example .env
npm install
npm run typecheck
npm run start
```

Use `EXPO_PUBLIC_API_BASE_URL` for the public LittleNet backend URL. Never copy backend secrets into this directory.

Replit should implement product screens on top of this foundation while keeping the API contract in `src/api/client.ts` and using v2 direct-upload/background-processing routes for media.
''',
)

write(
    ".github/workflows/ci.yml",
    r'''
name: LittleNet CI

on:
  push:
    branches: [main, master, react-native-migration]
  pull_request:

permissions:
  contents: read

jobs:
  source-audit:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'
      - uses: actions/setup-node@v4
        with:
          node-version: '22.13.0'
      - name: Install source-audit and test dependencies
        run: |
          python -m pip install --upgrade pip
          python -m pip install -r requirements-core.txt "pydantic>=2,<3" pytest
      - name: Run local source audits
        run: python tools/audit_all.py
      - name: Enforce parameterized SQL identifiers
        run: python tools/audit_dynamic_sql.py
      - name: Verify pinned MediaPipe assets
        run: |
          python tools/install_mediapipe_assets.py
          test -s static/vendor/mediapipe/vision_bundle.mjs
          test -s static/vendor/mediapipe/face_landmarker.task
          find static/vendor/mediapipe/wasm -name '*.wasm' -type f -size +100k | grep -q .

  secret-scan:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Gitleaks secret scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  python-security:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'
      - name: Install security scanners
        run: python -m pip install --upgrade pip pip-audit bandit
      - name: Audit web/runtime dependencies
        run: pip-audit -r requirements-core.txt --progress-spinner off
      - name: Bandit application scan
        run: >-
          bandit -r admin auth child childMessage parent quiz safety services uploadPost mobile
          -x tests
          -ll
          -s B608
''',
)

write(
    ".github/workflows/react-native.yml",
    r'''
name: LittleNet React Native

on:
  push:
    branches: [main, react-native-migration]
    paths:
      - 'mobile_app/**'
      - '.github/workflows/react-native.yml'
  pull_request:
    paths:
      - 'mobile_app/**'
      - '.github/workflows/react-native.yml'

permissions:
  contents: read

jobs:
  validate-mobile:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    defaults:
      run:
        working-directory: mobile_app
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22.13.0'
          cache: npm
          cache-dependency-path: mobile_app/package-lock.json
      - run: npm ci
      - run: npm run typecheck
      - run: npm run export:android
''',
)

write(
    ".github/workflows/release-mobile.yml",
    r'''
name: Build LittleNet Android with EAS

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build-android:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    defaults:
      run:
        working-directory: mobile_app
    env:
      EXPO_TOKEN: ${{ secrets.EXPO_TOKEN }}
      EXPO_OWNER: ${{ vars.EXPO_OWNER }}
      EXPO_PROJECT_ID: ${{ vars.EXPO_PROJECT_ID }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22.13.0'
          cache: npm
          cache-dependency-path: mobile_app/package-lock.json
      - name: Require Expo release configuration
        run: |
          test -n "$EXPO_TOKEN" || (echo 'Missing EXPO_TOKEN secret' && exit 1)
          test -n "$EXPO_OWNER" || (echo 'Missing EXPO_OWNER repository variable' && exit 1)
          test -n "$EXPO_PROJECT_ID" || (echo 'Missing EXPO_PROJECT_ID repository variable' && exit 1)
      - run: npm ci
      - name: Inject account-owned EAS identifiers for this build only
        run: |
          node - <<'NODE'
          const fs = require('fs');
          const p = JSON.parse(fs.readFileSync('app.json', 'utf8'));
          p.expo.owner = process.env.EXPO_OWNER;
          p.expo.extra = { ...(p.expo.extra || {}), eas: { projectId: process.env.EXPO_PROJECT_ID } };
          fs.writeFileSync('app.json', JSON.stringify(p, null, 2) + '\n');
          NODE
      - run: npx eas-cli@latest build --platform android --profile production --non-interactive --no-wait
''',
)

write(
    ".github/workflows/deploy-modal.yml",
    r'''
name: Deploy & Validate LittleNet Live

on:
  workflow_dispatch:
    inputs:
      live_url:
        description: Public HTTPS LittleNet backend URL
        required: false
        type: string
      migrate_database:
        description: Apply PostgreSQL schema/upgrades before validation
        required: true
        type: boolean
        default: true
  push:
    branches: [main]
    paths:
      - '.github/workflows/deploy-modal.yml'
      - 'modal_ai.py'
      - 'modal_web.py'
      - 'ai_server.py'
      - 'app.py'
      - 'auth/**'
      - 'safety/**'
      - 'services/**'
      - 'parent/**'
      - 'child/**'
      - 'childMessage/**'
      - 'uploadPost/**'
      - 'admin/**'
      - 'quiz/**'
      - 'mobile/**'
      - 'database/**'
      - 'db/migrations/**'

permissions:
  contents: read

env:
  LIVE_URL: ${{ inputs.live_url || vars.LITTLENET_LIVE_URL || 'https://littlenet655--littlenet-web-web.modal.run' }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    env:
      MODAL_TOKEN_ID: ${{ secrets.MODAL_TOKEN_ID }}
      MODAL_TOKEN_SECRET: ${{ secrets.MODAL_TOKEN_SECRET }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: python -m pip install --upgrade "modal>=1.5,<2"
      - name: Validate URL and Modal credentials
        run: |
          python - <<'PY'
          import os,sys
          url=os.environ.get('LIVE_URL','').strip().rstrip('/')
          if not url.startswith('https://') or 'localhost' in url or '127.0.0.1' in url:
              sys.exit(f'LIVE_URL must be a public HTTPS deployment, got {url!r}')
          PY
          test -n "$MODAL_TOKEN_ID"
          test -n "$MODAL_TOKEN_SECRET"
          modal token info
      - run: modal deploy modal_ai.py
      - run: modal deploy modal_web.py
      - name: Apply database schema and migrations
        if: ${{ github.event_name == 'push' || inputs.migrate_database }}
        run: modal run modal_web.py --init-db
      - run: modal run modal_web.py --seed
      - run: modal run modal_ai.py
      - run: modal run modal_web.py --preflight
      - name: Validate public readiness and mobile API
        run: |
          set -euo pipefail
          URL="${LIVE_URL%/}"
          curl --connect-timeout 10 --max-time 30 --fail-with-body -sS "$URL/healthz" | tee healthz.json
          curl --connect-timeout 10 --max-time 90 --fail-with-body -sS "$URL/readyz" | tee readyz.json
          curl --connect-timeout 10 --max-time 60 --fail-with-body -sS "$URL/api/mobile/v1/health" | tee mobile-health.json
          python - <<'PY'
          import json
          ready=json.load(open('readyz.json',encoding='utf-8'))
          mobile=json.load(open('mobile-health.json',encoding='utf-8'))
          if ready.get('status') != 'ready': raise SystemExit(f'Not ready: {ready}')
          if mobile.get('ok') is not True or mobile.get('client') != 'react-native':
              raise SystemExit(f'Mobile API identity mismatch: {mobile}')
          PY
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: littlenet-live-release-evidence
          path: |
            healthz.json
            readyz.json
            mobile-health.json
          if-no-files-found: ignore
          retention-days: 14
''',
)

write(
    "tools/audit_all.py",
    r'''
import shutil
import subprocess
import sys
from pathlib import Path

R = Path(__file__).parents[1]
steps = [
    [sys.executable, '-m', 'pytest', '-q'],
    [sys.executable, 'tools/preflight.py'],
    [sys.executable, 'tools/audit_routes.py'],
    [sys.executable, 'tools/audit_templates.py'],
    [sys.executable, 'tools/readiness.py', '--source-only'],
    [sys.executable, 'tools/scope_check.py'],
]
for cmd in steps:
    print('\n==>', ' '.join(cmd))
    result = subprocess.run(cmd, cwd=R)
    if result.returncode:
        raise SystemExit(result.returncode)

if shutil.which('node'):
    for rel in ['static/js/littlenet.js', 'static/js/live_safety.js', 'static/js/chat.js', 'static/js/stories.js']:
        print('\n==> node --check', rel)
        result = subprocess.run(['node', '--check', rel], cwd=R)
        if result.returncode:
            raise SystemExit(result.returncode)

required = [
    R / 'mobile_app/package.json',
    R / 'mobile_app/app.json',
    R / 'mobile_app/App.tsx',
    R / 'mobile_app/src/api/client.ts',
]
missing = [str(p.relative_to(R)) for p in required if not p.is_file()]
if missing:
    raise SystemExit('Missing React Native source: ' + ', '.join(missing))
if (R / 'mobile_flutter').exists() or (R / 'android').exists():
    raise SystemExit('Retired mobile source tree still exists')
if 'package.json' in (R / '.gitignore').read_text(encoding='utf-8').splitlines():
    raise SystemExit('package.json must be tracked')
print('\nREACT NATIVE SOURCE: PASS')
print('\nALL LOCAL SOURCE AUDITS PASSED')
''',
)

write(
    "tools/readiness.py",
    r'''
from pathlib import Path
import ast
import json
import sys

R = Path(__file__).parents[1]
checks = []


def add(name, ok, detail=''):
    checks.append((name, bool(ok), detail))


bad = []
for p in R.rglob('*.py'):
    if any(part in ('__pycache__', '.venv', 'venv', 'node_modules', '.git') for part in p.parts):
        continue
    try:
        ast.parse(p.read_text(encoding='utf-8'))
    except Exception as exc:
        bad.append(f'{p.relative_to(R)}:{exc}')
add('Python source parses', not bad, '; '.join(bad))

required = [
    'mobile/api.py', 'mobile/stitch_api.py',
    'mobile_app/package.json', 'mobile_app/app.json', 'mobile_app/App.tsx',
    'mobile_app/src/api/client.ts', 'mobile_app/.env.example',
    'safety/visual_service.py', 'safety/scene_sampler.py',
    'services/job_queue.py', 'services/media_processor.py',
    'modal_ai.py', 'modal_web.py', '.github/workflows/ci.yml',
    '.github/workflows/react-native.yml', '.github/workflows/release-mobile.yml',
    '.github/workflows/deploy-modal.yml',
]
for rel in required:
    add(rel, (R / rel).exists())

package = json.loads((R / 'mobile_app/package.json').read_text(encoding='utf-8'))
app = json.loads((R / 'mobile_app/app.json').read_text(encoding='utf-8'))
client = (R / 'mobile_app/src/api/client.ts').read_text(encoding='utf-8')
mobile_api = (R / 'mobile/api.py').read_text(encoding='utf-8')
visual = (R / 'safety/visual_service.py').read_text(encoding='utf-8')

deps = package.get('dependencies', {})
add('Expo SDK 57 declared', str(deps.get('expo', '')).startswith('57.'))
add('React Native 0.86 declared', str(deps.get('react-native', '')).startswith('0.86.'))
add('Android package contract', app.get('expo', {}).get('android', {}).get('package') == 'com.littlenet.app')
add('Public mobile env only', 'EXPO_PUBLIC_API_BASE_URL' in client)
add('v2 async upload routes mapped', '/api/mobile/v2/uploads/session' in client and 'processing-status' in client)
add('Mobile API identifies React Native', 'client="react-native"' in mobile_api and 'framework="expo"' in mobile_api)
add('Scene-aware video sampling active', 'combined_frame_indices(path,total,max_frames)' in visual)
add('Legacy mobile directories absent', not (R / 'mobile_flutter').exists() and not (R / 'android').exists())

print('LittleNet readiness')
for name, ok, detail in checks:
    print(('PASS' if ok else 'WAIT').ljust(5), name, ('- ' + detail) if detail else '')
source_ready = all(ok for _, ok, _ in checks)
print('\nSOURCE_READY=', source_ready)
raise SystemExit(0 if source_ready else 1)
''',
)

write(
    "tools/scope_check.py",
    r'''
from pathlib import Path
import sys

R = Path(__file__).parents[1]
checks = {
    'Kids Mode feed': ('child/routes.py', '/child/dashboard/'),
    'Posts/upload': ('uploadPost/routes.py', '/child/upload-post/'),
    'Reels': ('uploadPost/routes.py', '/reels/'),
    'Messages/chat': ('childMessage/routes.py', '/messages/'),
    'Discover': ('child/routes.py', '/discover/'),
    'Parent email OTP gate': ('auth/api.py', '/verify-parent-email/'),
    'Child face-first onboarding': ('auth/api.py', '/face/enroll/'),
    'Mandatory age onboarding quiz': ('auth/api.py', '/quiz/start/?onboarding=1'),
    '18+ hard block': ('safety/policy.py', '18+ content hard blocked'),
    'NSFW visual moderation': ('safety/visual_service.py', 'Falconsai/nsfw_image_detection'),
    'YOLO object detection': ('safety/visual_service.py', 'from ultralytics import YOLO'),
    'Scene-aware video sampling': ('safety/visual_service.py', 'combined_frame_indices(path,total,max_frames)'),
    'Cyberbullying/toxic NLP': ('safety/text_service.py', 'CYBERBULLYING'),
    'Parent review': ('parent/routes.py', '/parent/review/'),
    'Screen time': ('services/usage.py', 'SCREEN_TIME_LIMIT_REACHED'),
    'Smart parent controls': ('services/controls.py', 'educational_only_feed'),
    'Quizzes': ('quiz/routes.py', '/quiz/start/'),
    'Admin/Moderator': ('admin/routes.py', '/admin/moderation/'),
    'Face Login/liveness': ('safety/face_service.py', 'anti_spoofing=True'),
    'PostgreSQL activity logs': ('database/schema.sql', 'CREATE TABLE IF NOT EXISTS activity_logs'),
    'R2 media adapter': ('services/object_storage.py', 'uploads/r2/'),
    'React Native app source': ('mobile_app/App.tsx', 'LittleNet'),
    'Expo package contract': ('mobile_app/app.json', 'com.littlenet.app'),
    'Mobile bearer API': ('mobile/api.py', '/api/mobile/v1/health'),
    'v2 direct upload API': ('mobile/api.py', '/api/mobile/v2/uploads/session'),
    'v2 processing status API': ('mobile/api.py', '/api/mobile/v2/posts/<int:post_id>/processing-status'),
    'Async media job queue': ('services/job_queue.py', 'enqueue_media_job'),
    'Modal AI deployment': ('modal_ai.py', 'gpu="T4"'),
    'Quiet hours': ('services/controls.py', 'quiet_hours_state'),
    'Approved-only interaction': ('uploadPost/routes.py', 'approved connection required'),
}
errors = []
for name, (rel, needle) in checks.items():
    p = R / rel
    ok = p.exists() and needle in p.read_text(encoding='utf-8')
    print(('PASS' if ok else 'FAIL'), name)
    if not ok:
        errors.append(name)

negative = {
    'Standalone speech dependency removed': ('requirements-ai.txt', 'openai-whisper'),
    'Legacy mobile source removed': ('mobile_flutter', None),
    'Duplicate Android root removed': ('android', None),
    'Old native release workflow removed': ('.github/workflows/release-android.yml', None),
}
for name, (rel, forbidden) in negative.items():
    p = R / rel
    ok = not p.exists() if forbidden is None else (not p.exists() or forbidden.lower() not in p.read_text(encoding='utf-8').lower())
    print(('PASS' if ok else 'FAIL'), name)
    if not ok:
        errors.append(name)

print(f'\nSCOPE_CHECK={len(checks)+len(negative)-len(errors)}/{len(checks)+len(negative)}')
sys.exit(bool(errors))
''',
)

write(
    "tools/verify_release.py",
    r'''
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ZIP = ROOT.parent / 'LittleNet-complete-release.zip'
if not ZIP.exists():
    raise SystemExit('Release ZIP not found; run tools/package_release.py first')

required = [
    'README.md', 'BUILD_STATUS.md', 'SCOPE_STATUS.md', '.env.example',
    'app.py', 'modal_ai.py', 'modal_web.py', 'mobile/api.py', 'mobile/admin_api.py',
    'mobile_app/package.json', 'mobile_app/package-lock.json', 'mobile_app/app.json',
    'mobile_app/App.tsx', 'mobile_app/src/api/client.ts',
    '.github/workflows/react-native.yml', '.github/workflows/release-mobile.yml',
    '.github/workflows/deploy-modal.yml',
]
errors = []
with zipfile.ZipFile(ZIP) as z:
    names = z.namelist()
    for name in required:
        if name not in names:
            errors.append(f'missing release file: {name}')
    for name in names:
        p = Path(name)
        if p.name in {'.env', 'local.properties'}:
            errors.append(f'forbidden file: {name}')
        if any(part in {'.git', '.pytest_cache', '__pycache__', '.venv', 'venv', 'node_modules', 'mobile_flutter'} for part in p.parts):
            errors.append(f'forbidden runtime/legacy path: {name}')
        if p.parts and p.parts[0] == 'android':
            errors.append(f'forbidden duplicate Android root: {name}')
        if p.suffix in {'.pyc', '.pyo', '.jks', '.keystore', '.apk', '.aab'}:
            errors.append(f'forbidden build/sensitive suffix: {name}')

print('RELEASE_FILES', len(names), 'ERRORS', len(errors))
for error in errors:
    print('-', error)
sys.exit(bool(errors))
''',
)

# Remove obsolete documentation that still instructs agents around the retired client.
for md in ROOT.rglob("*.md"):
    if any(part in {"node_modules", ".git"} for part in md.parts):
        continue
    if md.name in {"README.md", "AGENTS.md", "STACK.md", "BUILD_STATUS.md", "SCOPE_STATUS.md", "REPLIT.md"}:
        continue
    try:
        if "flutter" in md.read_text(encoding="utf-8", errors="ignore").lower():
            md.unlink()
    except OSError:
        pass

# This preparer and its bootstrap workflow are one-shot and must not survive the migration commit.
remove(".github/workflows/prepare-react-native.yml")
this_file = Path(__file__)

# Final hard guard: no active source/config should retain the retired framework name.
this_file.unlink()
for path in ROOT.rglob("*"):
    if not path.is_file() or any(part in {".git", "node_modules"} for part in path.parts):
        continue
    if path.suffix.lower() not in {".py", ".md", ".yml", ".yaml", ".json", ".toml", ".sh", ".js", ".ts", ".tsx", ".txt"}:
        continue
    text = path.read_text(encoding="utf-8", errors="ignore").lower()
    if "flutter" in text:
        raise SystemExit(f"Retired framework reference remains in {path.relative_to(ROOT)}")

if (ROOT / "mobile_flutter").exists() or (ROOT / "android").exists():
    raise SystemExit("Legacy mobile directories remain")
if re.search(r"(?m)^package(?:-lock)?\.json$", (ROOT / ".gitignore").read_text(encoding="utf-8")):
    raise SystemExit("Node package manifests are still ignored")

print("React Native/Replit repository migration prepared successfully")
