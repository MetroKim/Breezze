# Breezze Backend — Run Guide

Branch `breezze` · 24 modules · 31 schema models · media pipeline workers

## Quick start (full stack)

```bash
git clone -b breezze https://github.com/MetroKim/MetroMusic.git
cd MetroMusic/backend
cp .env.example .env       # configure secrets before production
docker compose up -d          # postgres, redis, api, ytmusicapi metadata service, worker
```

The API is then at `http://localhost:3000/api/v1` (Swagger at `/api/docs`). The provider registry exposes `GET /api/v1/providers` and YouTube Music metadata search at `GET /api/v1/providers/youtube_music/search?q=...` and track metadata at `GET /api/v1/providers/youtube_music/tracks/{videoId}`. The sidecar is internal to the Compose network and is not published as a public port.

For production, set `NODE_ENV=production`, generate `EDGE_SHARED_SECRET` and `MEDIA_SIGNING_KEY` with `openssl rand -hex 32`, and keep the values in your deployment secret manager. `EDGE_SHARED_SECRET` must match the API Worker secret. Do not use the development defaults.

## First-time setup (migrations + client)

```bash
cd backend/api
npm install
npx prisma migrate dev --name init
```

## Media pipeline

Upload flow: `POST /api/v1/media/uploads` registers the job (status
`quarantined`) and enqueues it. The worker process validates with
FFprobe, transcodes to HLS (aac_128 + aac_256), and marks the record
`published`. Job status is visible in `GET /api/v1/media/jobs`.

The worker needs FFmpeg — the compose `worker` service ships with it.
To run the worker locally outside Docker: `ffmpeg` must be on PATH,
then `npm run start:workers`.

## Free app

Breezze has no subscriptions and no billing — users get the full
experience for free. There are no subscription or payment tables in
the schema and no paywall UI in the apps.

## Known gaps (tracked in MODULES.md)

- Admin RBAC role-gate pending
- Search is contains-based (pg_trgm upgrade when measured)
- YouTube Music adapter is metadata/discovery only; it does not supply playback URLs or streaming rights
- Production Cloudflare routing requires matching `EDGE_SHARED_SECRET` in the API deployment and Worker secret store; see `infra/cloudflare/api-worker/README.md`
- CI workflow file must be added manually (GitHub workflow-scope
  write is blocked for the agent)
