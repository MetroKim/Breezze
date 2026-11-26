# Breezze full-length music: practical, authorized playback plan

**Goal:** Offer full songs in Breezze's one native player and legal offline listening without representing search/catalog metadata as audio rights. **State:** local owned full-length test playback implemented; production rights-cleared partner catalog not certified.

## Route A — immediately implementable for user-owned music

The Flutter PlayerController already accepts `localFilePath` and the integration test generates/decodes a 125-second original test tone. Support personal files selected by the user in the Library without uploading, extracting or distributing them. Preserve OS portal/scoped-storage access, local-only provenance, account separation and original metadata. A file in the user's possession is **not** a grant for Breezze to rehost it in a shared catalog.

Acceptance: authorized 125-second local WAV/FLAC/AAC plays fully, seeks beyond 100 seconds, handles background/pause/focus correctly, and does not create a remote entitlement. Explicit `device:` tracks are not provider metadata.

## Route B — Breezze-hosted full-length streaming and offline

1. **Acquire explicit rights** for both the recording (master) and musical composition, in writing. Contract must identify rightsholder, allowed territories, streaming/offline uses, term, takedowns and attribution. A Creative Commons or public-domain claim must be independently verified for *all relevant rights*; NC/ND and territory rules matter.
2. **Curate a licensed internal catalog** with `breezze_internal` tracks, rightsUsagePermission `stream.full` and separate `offline.download`, territoryAvailability records and takedown controls. Do not create grants solely from external metadata IDs or arbitrary direct URLs.
3. **Ingest controlled source audio** via the privileged admin pipeline into private R2, encode to supported AAC/FLAC variants, record SHA-256 and exact verified byte count, and mark the variant ready only after verifying storage integrity.
4. **Resolve per play** through the authenticated API and trusted Cloudflare country header. Enforce allowed territory, live permission window, quality ceiling, active takedowns and existence of the exact variant before issuing short-lived HMAC-signed media-worker URLs. The native player fetches via HTTP Range and renews expired grants only through the API.
5. **Offline is separate:** issue a per-user leased download authorization only if `offline.download` is explicitly licensed; encrypt the account-scoped file and enforce lease revalidation, revocation and deletion on logout or rights loss.
6. **Verify in layers:** TypeScript/Prisma/Worker tests + a 125-second synthetic file through isolated QA R2 (full bytes, far range, expiration and tamper denial), then a licensed internal track through production-equivalent staging, then physical phone/desktop decoding and offline testing. Do not use a production copyrighted track as a QA workaround.

**New capability proof:** `.github/workflows/media-live-qa.yml` was extended to generate a 125-second synthetic AAC, upload it to isolated `breezze-media-qa`, validate entire downloaded bytes and duration using `cmp`/`ffprobe`, request the last 1024 bytes and reject forged signatures. The workflow requires QA Cloudflare GitHub secrets and a **manual dispatch**. Its existence is not evidence it already passed.

## Route C — existing third-party catalog experiences

- **YouTube Music:** metadata/discovery via `ytmusicapi` only; use the official visible YouTube player for authorized video playback under YouTube's API terms. Do not strip audio, cache/download video or call the iframe a native full-song audio source.
- **Spotify:** official metadata; Spotify authorization does not grant raw AAC/FLAC for Breezze. Direct the user to official Spotify playback where appropriate. Partner SDK features (if eligible) require separate agreements, platform/user subscriptions and UX disclosure.
- **Deezer:** limited official provider preview is not a full-song stream or download grant. Deezer ARL/cookies are **not** a durable or approved production media source.
- **Apple Music:** MusicKit is a separately evaluated integration requiring Apple approval/user entitlement; it cannot be represented as free unrestricted native playback.
- **Indie label / original artist catalog:** strongest way to offer full tracks without a per-user subscription *if* Breezze secures written licenses and sustainable royalty/legal terms. Start with artist-direct fully authorized tracks and test in selected territories; expand as contracts permit.

## Policy for release

A full-length **synthetic** QA recording proves **technical capability only**. A production song requires verified rights provenance, approved territory, separate offline rights, server grants, tested storage and device playback. A public-domain license isn't a bypass for recorded-performance or composition rights. No release can claim an unlimited YouTube/Spotify catalog without independent authorization.

Architecture references: `backend/api/src/playback/playback-resolve.service.ts`, `backend/api/src/rights/rights-decision.service.ts`, `apps/mobile/lib/core/audio/authorized_download_grant.dart`, `infra/cloudflare/media-worker/src/index.ts`.
