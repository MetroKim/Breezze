# Breezze

**A free, listener-first music platform built with Flutter and NestJS.**

Breezze is an independent product. It is not affiliated with or endorsed by YouTube, Google, Spotify, Apple, or another streaming service.

> **Single authoritative version: V8.** [Breezze Unified Engine V8 — implementation and acceptance plan](docs/BREEZZE_UNIFIED_ENGINE_V8_IMPLEMENTATION_PLAN.md) governs navigation, architecture, catalog/media rights, frontend/backend wiring and all quality gates. Earlier plan versions are retired; historical commits remain available for audit. Breezze is still in development and must not be released or newly deployed before complete verification and explicit owner approval.

## Active implementation

The production-target client is Flutter in `apps/mobile`, with NestJS in `backend/api` and the Python discovery service in `backend/ytmusicapi`. The unused Kotlin/Chordline app trees have been removed from this checkout; their historical commits remain in Git. License and attribution obligations are retained and must be reviewed before distribution. Run Flutter builds from `apps/mobile`.

**Auth migration:** `main` still contains its working legacy authentication endpoints. Supabase Auth and the custom login screens are being integrated separately; do not delete or disable the live auth path before that rollout passes integration tests.

## Product boundaries

- Four primary destinations: Home, **New**, Library and Search. New replaces the former Browse label.
- One global player and queue shared by every screen.
- No artist portal, artist upload workflow, subscriptions, billing, memberships or paywalls in this release.
- Artist and album pages are listener-facing catalog experiences only.
- Search metadata is not a playback licence. Playback requires a backend-authorized source with applicable rights.
- Spotify and Deezer metadata/discovery (and allowed short previews) are separate from playback rights; YouTube Music through `ytmusicapi` supplies discovery metadata and official embedded video. Breezze owns its native player and queue, which require independently authorized recordings and media grants.
- Breezze does not extract YouTube audio, bypass provider access controls, or re-host third-party recordings.

## Repository layout

```
apps/mobile/               Flutter client and platform adapters
packages/design_system/    Breezze tokens, themes, components and SVG icons
packages/audio_contracts/  Playback state, queue and engine contracts
packages/api_client/       Typed Breezze API client
backend/api/               NestJS API, Prisma/PostgreSQL, Redis and BullMQ
backend/ytmusicapi/         Python music metadata/discovery adapter
infra/cloudflare/          API edge, WAF, rate limits and public metadata cache
docs/                      Product, design, architecture, legal and release records
```

## Launch Breezze on Linux or GitHub Codespaces

Run `bash run.sh` from the repository root. It automatically opens the Flutter
application under `apps/mobile`, installs dependencies, generates Drift database
code, prepares browser SQLite assets, and starts the native Linux desktop when
a GUI is available. In GitHub Codespaces/headless environments, it starts a
browser preview on port 8080; open that port in the **Ports** panel.

The Linux runner is tracked in Git to support `flutter run -d linux` after
app dependencies and generated database code are ready. Use `bash run.sh linux`
to force native Linux, or `bash run.sh web` for the browser. Set
`BREEZZE_API_URL` to use a different backend and `BREEZZE_PORT` to change
the preview port.

Do not run `flutter run` from the monorepo root: `pubspec.yaml` lives in
`apps/mobile`.

## Quick start

### Flutter client

From the repository root:

```bash
cd apps/mobile
bash tool/generate_platform_targets.sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --reporter expanded
flutter run --dart-define=BREEZZE_API_URL=http://localhost:3000
```

The platform generator creates the native runner folders and applies the required Android foreground-media and iOS background-audio declarations. It does not install platform SDKs, configure signing, or certify physical-device playback.

### Backend

```bash
cd backend/api
npm install
docker compose up -d
npx prisma generate
npx prisma migrate dev
npm run typecheck
npm test -- --runInBand
```

The local API defaults to `http://localhost:3000`; Swagger is exposed at `/api/docs`. For a physical phone, `localhost` is the phone itself: pass the computer's LAN API address during local development (for example, `--dart-define=BREEZZE_API_URL=http://192.168.x.x:3000`) or use the public HTTPS Cloudflare API URL. Release builds refuse API calls without a configured HTTPS `BREEZZE_API_URL`, preventing production from silently targeting localhost. Configure provider credentials only in backend environment/secrets. Never place provider secrets in Flutter or commit them.

## Audio and provider architecture

- Flutter uses one global `PlayerController` backed by the shared audio-engine adapter.
- The NestJS backend owns canonical track identity, provider selection, rights checks and playback resolution.
- Audius and Jamendo are removed. Full songs require separately authorized recordings with valid territorial `stream.full` rights; neither YouTube Music metadata nor Deezer preview links grant full-song streaming permissions.
- YouTube Music metadata is never passed to the native audio engine as a playable source.
- Audio is streamed directly from an approved provider to the device by default. Cloudflare Workers and NestJS do not proxy audio segments.
- Local files remain user-controlled. Offline downloads require explicit download rights and backend authorization.

## Platform targets

The Flutter codebase targets Android, iOS, Web, Linux, macOS and Windows. Build each target on its supported host and validate the actual media-session behavior there. CI compilation is not a substitute for real-device playback, background-audio, Bluetooth-route and lock-screen testing.

## Documentation index

- [Product experience](docs/PRODUCT_EXPERIENCE.md)
- [Interface contract](docs/design/BREEZZE_INTERFACE_CONTRACT.md)
- [Integrated design and engineering architecture](docs/architecture/BREEZZE_INTEGRATED_DESIGN_ENGINEERING_ARCHITECTURE.md)
- [Multi-source provider architecture](docs/architecture/BREEZZE_MULTISOURCE_PROVIDER_ARCHITECTURE.md)
- [Provider integration decision](docs/architecture/BREEZZE_PROVIDER_INTEGRATION_DECISION.md)
- [Discovery provider setup](docs/architecture/DISCOVERY_PROVIDER_SETUP.md)
- [Cloudflare and caching architecture](infra/cloudflare/README.md)
- [One-million-active-listener scaling plan](docs/architecture/BREEZZE_ONE_MILLION_SCALING_PLAN.md)
- [Security and production checklist](docs/PRODUCTION_SECURITY_AND_CACHING_CHECKLIST.md)
- [Current implementation gap register](docs/audit/gap-register.md)
- [Engineering backlog](docs/ROADMAP_AND_BUG_BACKLOG.md)
- [Third-party code and provider policy](docs/legal/BREEZZE_THIRD_PARTY_CODE_POLICY.md)

## Current verification

The pre-cleanup `main` baseline `c74b98cdf3e17dee26367cc2d3237d09f76bbf0b` passed [CI](https://github.com/MetroKim/Breezze/actions/runs/45165004967), [Flutter web preview smoke](https://github.com/MetroKim/Breezze/actions/runs/45165004943), and [CodeQL](https://github.com/MetroKim/Breezze/actions/runs/45165004941). Cleanup commits require their own post-change CI checks; this paragraph does not claim physical-device or streaming-rights verification.

Breezze's one-million-active-listener goal is an engineering target, not a measured capacity claim. Production deployment, provider rights approval, load testing and physical-device certification remain release gates.


### Production connectivity and deployment

- The API exposes `GET /health` for origin/container health checks.
- Production container template: `backend/docker-compose.production.yml`. Copy `backend/.env.production.example` to `.env.production`, generate unique secrets, then run `docker compose --env-file .env.production -f docker-compose.production.yml up -d --build` from `backend/`.
- Deploy the NestJS origin first on a host with a public HTTPS origin (or a Cloudflare Tunnel). Then configure `BREEZZE_API_ORIGIN`, `EDGE_SHARED_SECRET`, `CLOUDFLARE_API_TOKEN`, and `CLOUDFLARE_ACCOUNT_ID` as GitHub Actions secrets and run the **Deploy Breezze API edge** workflow. Set `BREEZZE_API_PUBLIC_URL` to the public Worker/custom-domain URL for its post-deploy smoke check.
- Build release clients with `--dart-define=BREEZZE_API_URL=https://YOUR-API-HOST`; never ship a release build with a localhost URL.
- Deployment credentials and a real hosting origin are not stored in this repository. Green CI proves compilation/tests, not that a production origin is deployed or reachable.
