# Breezze

**An open music platform — one Flutter client, one NestJS backend.**

Breezze is an independent product. It is not affiliated with, endorsed by, or
connected to YouTube, Google, Spotify, Apple, or any streaming platform.

> The `main` branch is the active Breezze project. The earlier Kotlin Multiplatform
> Chordline prototype has been retired.

## Repository layout

```
apps/mobile/               Flutter client (Riverpod, Drift/SQLite, just_audio, audio_service)
packages/design_system/    Breezze tokens, themes, Atmosphere materials, components
packages/audio_contracts/  Playback contracts — state machine, queue, engine adapter, LRC
packages/api_client/      Provider + download library contracts
backend/api/               NestJS modular monolith (PostgreSQL, Prisma, Redis, BullMQ)
infra/cloudflare/          Cloudflare Worker + private R2 media gateway
docs/audit/                Honest per-requirement status (gap register)
```

## Quick start

### Mobile

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter create .   # first checkout only — platform runners are not committed
flutter run
```

### Backend

```bash
cd backend/api
npm install
docker compose up -d
npx prisma migrate dev
```

The API serves `http://localhost:3000/api/v1` (Swagger at `/api/docs`).

## Principles

- **Playback first** — one global PlayerController; screens never own audio.
- **Honest results** — no fake URLs, no placeholder data presented as real.
- **Server-side authorization** for everything protected.
- **Free** — no payments, no paywalls, no subscription tables.

See `docs/audit/gap-register.md` for what is implemented and what is not.
