# Breezze completion and integration matrix — 25 November 2026

**Authoritative product:** `MetroKim/Breezze`, independent `main`. This is a factual release audit, **not** a statement that every product feature is implemented or legally licensed. Use actual deployment commits, runtime tests and platform acceptance as the final evidence. Source files alone do not prove production functionality.

## Confirmed source and platform evidence

- Baseline independent main at `a3d30ad5be255fbb7e300d8d53c26373c1ee7af5`: 9/9 CI jobs passed, CodeQL and web-preview smoke passed. Android emulator acceptance run `45571825901` passed.
- The same main's iOS simulator acceptance run `45571826000` was **cancelled**; it did not pass. The Android/iOS workflow global concurrency groups could cancel a main run when a feature branch pushed. PR #67 scopes both groups to `github.ref`. An iOS pass on a **new, exact main SHA** is still required.
- Verified source migration: all 477 original fork-main tracked paths are represented on independent main. Unique historical branch commits remain separately held in `MetroKim/Breezze-legacy-fork`; do not delete this archive until independently preserved.
- Exact user-supplied visual sources have one canonical repository location: `docs/design/reference/`. PR #67 removes seven byte-identical duplicate blobs from `docs/design/legacy-handoff/` after comparing Git blob hashes, and preserves checksum/ZIP/PNG/SVG verification via the existing CI entrypoints.

## Connected infrastructure — live observed state

| Layer | Current evidence | Remaining acceptance |
| --- | --- | --- |
| Flutter | Single app under `apps/mobile/`, four tabs; CI builds Android/iOS/web/desktop | Emulator/device usability, signed-in flows, interruption, offline rights and performance testing on exact release |
| API gateway | Railway project Breezze, service `Breezze API` sourced from `MetroKim/Breezze` main at deployed `13b6c9e`; healthcheck `/health`; predeploy `prisma migrate deploy` | The current main SHA is **newer** than production. Preflight migrations, compatible authorization, backup and smoke; then release and verify deployed commit |
| Public metadata | Railway `Breezze Catalog Metadata` (private FastAPI sidecar) last deployed from `7239b1a` | Verify new ytmusicapi endpoints and adapter compatibility against current source; redeploy only after contract tests |
| Edge/CDN | Cloudflare has `breezze-api-edge` last modified 22 Nov and `breezze-media` last modified 23 Nov | Verify exact Worker revision/routes, origin secret, callback edge bypass for approved OAuth, and production smoke after coordinated deployment |
| Identity | Supabase project `djwvyjtebmsavhcrmhxf` is `ACTIVE_HEALTHY`; Google/email sign-in intended, Apple pending | Real Google/iOS/Android OAuth registration and account lifecycle tests; keep sign-in gate required |
| Database | Railway Postgres + Redis are live and have persisted volumes; Supabase public schema separately contains `profiles`, `user_library`, `pinned_playlists` with RLS, 0 rows in the inspected tables | **Two distinct Postgres systems exist.** Confirm system of record and migration/reconciliation plan; never switch `DATABASE_URL` or delete Railway Postgres without a verified backup and data migration. Zero public rows do not imply zero Supabase Auth users |
| Separate YouTube consent | Current NestJS code has owner-bound OAuth/PKCE, private encrypted tokens and readonly YouTube playlist APIs | Production `YOUTUBE_ACCOUNT_LINK_ENABLED` is not enabled; dedicated Google OAuth client, verified redirect URI/scope and YouTube Data API v3 acceptance remain external preconditions |

## YouTube Music client implementation contract

The existing Breezze YouTube Music companion provides public catalog Explore, trending, albums, playlists, moods, artist profiles and charts through one authenticated Breezze API client. Read-only YouTube Data API playlists use separate user consent. PR #67 adds song search and related-track discovery through already-existing provider endpoints, and safeguards linked-account data when the Breezze listener switches.

`sigma67/ytmusicapi` is a best-effort unofficial metadata interface, **not** a licensed full-song streaming or offline download right. Official visible YouTube video playback is a separate surface. Breezze's native `just_audio` queue may play local and server-authorized licensed assets or approved bounded provider previews, but must never turn YouTube metadata into a hidden audio grant. Do not add a second player or a raw stream scraper to claim completeness.

### Next YouTube milestones — do not mark done until verified

1. Public catalog navigation: song search, suggestions, artist/album/playlist drill-down, search empty/partial/error states, verified ID and source validation. **PR #67 under review.**
2. Dedicated Google YouTube readonly OAuth: verify Cloudflare callback, client registration, state/PKCE, secret storage, owner isolation, token refresh/revoke and disabled-state UX against production.
3. Native playback rights: obtain a permitted and contractually reviewed full-song source if full-track streaming is required; test country, entitlement, expiry, pause/resume, background mode and royalties. YouTube Data API or ytmusicapi alone does not satisfy this.
4. Library/queue parity: owner-scoped playlists, liked/saved catalog representations, repeat/shuffle/reorder across authorized playable sources; never represent metadata-only watch suggestions as the global native player queue.
5. Premium UX and accessibility: component-led monochrome art-forward surfaces, responsive tablet/desktop navigation, artwork caching, motion preferences, focus/screen-reader semantics, text scaling, UI golden/screenshot tests and emulator visual signoff.

## Safe cleanup policy

- **Remove proven duplicate/unreferenced active files only.** Confirm identical Git blob hashes or zero code/runtime references and update tests/docs before deletion.
- Preserve original user ZIPs/SVGs, license notices, historical patches and old fork branches in their canonical archive until auditable. Do not delete production databases, user media, migrations, secrets or unreviewed branches as file cleanup.
- The old `radio.svg` remains inside the preserved original icon inventory; retaining historical source is not the same as exposing a Radio tab.
- Legacy `AUDIUS_*` and `JAMENDO_*` Railway variable *names* exist. Determine their values/consumers through authorized configuration review before removing them. A leftover variable name is not proof of active provider routing.

## Definition of a verified 100% working release

Required: authoritative main PR merges only after exact-head CI passes; zero failing CodeQL checks; Android and iOS emulator acceptance at exact main SHA; production API/Worker/metadata service versions reconciled to compatible source; additive Prisma migrations and production smoke tested without user-data loss; Supabase and YouTube OAuth callbacks verified end-to-end where enabled; licensed full-track/offline entitlements separately proven; on-device functional, performance, visual and accessibility checks complete. Until these conditions are met, release status is **INCOMPLETE**, even if every repository test is green.
