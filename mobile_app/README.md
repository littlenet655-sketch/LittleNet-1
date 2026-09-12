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
