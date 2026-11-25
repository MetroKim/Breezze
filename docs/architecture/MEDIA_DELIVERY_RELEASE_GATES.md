# Breezze Media Delivery — Production Release Gates

**Status as inspected 2026-11-26:** Engineering and tests continue on GitHub `main`. The existing production release freeze is **not** authorization to publish an app or deploy unverified media code. No unauthorized YouTube audio rehosting or offline copies.

## 1. Verified environment inventory

| Component | Inspected state | Remaining gate |
| --- | --- | --- |
| GitHub `MetroKim/Breezze` | Main has signed private R2 Worker and rights-gated NestJS audio/video modules | Latest CI and release approval |
| Railway `Breezze API` | Running, `/health` returns 200; deployed revision `13b6c9e` | Catch up with reviewed main revision after staging verification |
| Railway `Postgres` | Live production service; NestJS has a `DATABASE_URL` binding | Confirm full migrations, back up before changes |
| Supabase `djwvyjtebmsavhcrmhxf` | Healthy; `public` presently has `profiles`, `user_library`, `pinned_playlists` | Do **not** assume Prisma tables are present or move production data without tested migration |
| Cloudflare `breezze-api-edge` | Worker exists; `/health` forwards successfully to Railway | Recheck origin secret, territory trust and latency after API deploy |
| Cloudflare `breezze-media` | Worker and secret binding exist; private R2 bucket exists; `/health` on deployed revision currently responds 404 | Deploy verified current Worker release to an approved staging target first |
| R2 `breezze-media` | No objects listed during audit | Ingest an owned/sufficiently licensed recording; verify storage and license state |

The Supabase public tables and Railway Postgres are **not** interchangeable by name. Until an explicit migration is accepted and verified, treat the existing Railway Postgres as the API's current operational database and Supabase as the identity/profile layer. Do not dual-write canonical media rights or perform destructive migrations.

## 2026-11-26 verified follow-up (do not confuse QA with production)

- Source revision `d241f3a`: the no-deploy media verification jobs passed (NestJS rights tests and local Wrangler/R2 real HTTP ingest/seek tests).
- GitHub run [45712075608](https://github.com/MetroKim/Breezze/actions/runs/45712075608): **three jobs PASS**, including applying the real Prisma migration history on a fresh PostgreSQL 16 instance and running the actual audio-catalog database integration test.
- A dedicated **non-production** Cloudflare Worker `breezze-media-qa` now runs the current media source with an isolated private R2 bucket `breezze-media-qa`; its remote `/health` returned HTTP 200, and an invalid signed-media request returned HTTP 403. This does **not** certify a live, authorized audio recording; the production media Worker is unchanged.
- The separate `media-live-qa.yml` workflow is manual-only: repository Cloudflare deployment secrets were not configured during its first invocation. The QA Worker was instead deployed through the connected Cloudflare API. It is **not** permissible to treat this first GitHub Actions attempt as successful or to copy a production secret into GitHub.
- The global native Flutter test has been extended to verify a 125-second original WAV file, far seeking, pause and resume on Android and iOS runners. Acceptance for the *new revision* remains pending until both simulators complete successfully.
- The NestJS protected `/health/ready` endpoint checks media schema availability at runtime while the public `/health` remains a shallow liveness probe. This endpoint needs a reviewed **backend deployment** before it exists on Railway.

## 2. Current contract

`apps/mobile` maintains one authoritative playback coordinator and queue. NestJS owns the recording identity, rights, country-specific availability, and issuance of a session/short-lived media grant. The private Cloudflare media Worker authenticates the grant before responding to HEAD, GET or byte-range GET. R2 stores only Breezze-owned or separately rights-cleared AAC/FLAC and MP4 files. Official YouTube video playback remains with the official visible player.

A `ytmusicapi` metadata row does **not** grant native audio or download rights. A catalogue match may reference a distinct, authorized internal recording only when approved with evidence. Deezer previews are not full-song grants.

## 3. Developer and CI acceptance (does not require third-party music rights)

From repository root:

```bash
cd backend/api
npm install --no-audit --no-fund
npx prisma generate
npm run typecheck
npx jest --runInBand src/downloads/downloads.service.spec.ts src/admin/audio-catalog.service.spec.ts src/playback/playback-resolve.service.spec.ts

cd ../../infra/cloudflare/media-worker
npm install --no-audit --no-fund
npm run check
npm test
npm run test:http
```

`test:http` starts a real local Wrangler/workerd server against **local**, isolated R2 data. It generates an original 2-second AAC MP4 with FFmpeg, uploads it with a signed ingest grant and checks object immutability, streaming, HEAD, byte ranges, download purpose and forged/expired grants. The test removes its synthetic recording and local state afterward. It **does not** insert fixtures into production R2, use a real listener account, or certify YouTube Music rights.

The independent GitHub workflow is `.github/workflows/media-delivery-verify.yml`. Do not mark green until its latest complete run passes **both** jobs.

## 4. Controlled staging and real-asset acceptance

1. Preserve the current Railway deployment/DB backup and Cloudflare Worker version. Do not modify production credentials or release freeze.
2. Deploy the updated media Worker to an approved staging route and dedicated staging R2 bucket; configure a strong staging-only `MEDIA_SIGNING_KEY` and non-public bucket binding. Never reuse production signing credentials in a development test.
3. Create an **internal** catalog recording with documented ownership/license, trusted source `breezze_internal`, `TerritoryAvailability`, and explicit current `RightsUsagePermission` for `stream.full` (and separately `download` if applicable). An uploaded file is not equivalent to a rights grant.
4. With an authenticated admin, call `POST /admin/audio-catalog/issue-ingest` for the exact quality and MIME. Upload verified bytes using only the returned short-lived capability. Do not accept arbitrary `url` or object key from the app.
5. Call `POST /admin/audio-catalog/verify-asset`. This must recheck rights and takedowns, perform a real CDN HEAD and record `AudioAssetVariant` as `ready` only after content validation.
6. With an authenticated listener in a trusted edge-derived country, call `POST /playback/sessions` with the internal `trackId`. Verify `streamUrl`, expiry, codec and correct MIME; then GET, HEAD, Range `bytes=0-1023`, resume seeks and expiry/forgery denial. Test download separately from a full-stream grant.
7. Run Android **and** iOS emulator playback from Breezze: play/pause, 30+ seconds, queue auto-advance, seek, network drop/recovery, interruptions, lock-screen controls, and route changes supported by the simulator. Save logs/CI evidence; emulator Bluetooth is not a replacement for physical-device verification.
8. Confirm download storage encryption and lease enforcement on the client before enabling offline playback. CDN download authorization alone does not prove that offline files are encrypted or revoked locally.
9. After explicit release signoff, promote reviewed revisions with rollback targets. Compare post-deploy health and version with GitHub SHA; run the same staging smoke against licensed content without leaking signed URLs into logs.

## 5. Database cutover gate

- Inventory Railway Prisma schema, migration history, application row counts, and foreign keys (read-only first).
- Inventory Supabase `public` and `auth` objects and RLS. The current Supabase project has only three `public` tables, not the entire NestJS/Prisma schema.
- If Supabase PostgreSQL becomes the authoritative API database, perform a backup, compatible schema migration and data mapping in **staging** first. Preserve identity joins and existing UUIDs; ensure `auth.users` remains Supabase-managed. Run Prisma migrations with the intended connection role, and check RLS/Data API exposure before any cutover.
- Dual-write to two authoritative catalog/rights tables is forbidden. Cut over by one clearly defined source-of-truth change, with rollback and checks of counts, permissions and foreign keys.

## 6. Blockers that engineering cannot fake

- The published YouTube Data API and standard YouTube players do **not** expose a general licensed, separable full-song YouTube Music audio feed for third-party native player use. Only an explicit distribution arrangement or another authorized source can supply that right.
- A successful synthetic AAC test proves the **pipeline**, not availability of full commercial recordings.
- A healthy Worker with an empty R2 bucket has no songs to serve.
- Production/backend release and real Android/iOS media acceptance remain **unverified** until their corresponding tests and approvals finish.

**Release policy:** Keep the product in development; do not publish app releases, source archives or public media grants to close a test. Recording rights, client performance and tested revision parity must all be demonstrated.
