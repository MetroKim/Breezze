# Breezze Current Implementation Gap Register

**Last reconciled:** 2026-11-22  
**Active implementation branch:** `feat/breezze-audio-engine-foundation`  
**Current proposal:** [PR #8](https://github.com/MetroKim/MetroMusic/pull/8)  
**Related provider proposal:** [PR #7](https://github.com/MetroKim/MetroMusic/pull/7)

This file is the current release-status reference. A capability is not marked release-ready merely because a class, screen, endpoint or configuration exists. It needs implementation, automated tests, CI evidence, provider/rights approval where relevant, and platform validation.

## Product scope — current release

- Listener-facing Breezze app only.
- Five destinations: Home, Browse, Radio, Library and Search.
- No artist portal, artist upload workflow, subscription, membership, billing, paywall or paid tier.
- Artist/album/playlist pages, where implemented, are consumer catalog pages—not artist management tools.
- No third-party audio extraction or unauthorized re-hosting.
- No R2-hosted third-party music. Approved provider audio is delivered directly to the device by default.

## Verified repository direction

| Area | Current state | Evidence / remaining gate |
|---|---|---|
| Flutter architecture | One Flutter application codebase for Android, iOS, Web, Linux, macOS and Windows | Platform runner generator and CI build matrix; each target still needs supported-host/device validation |
| Global playback | One global PlayerController and one shared native audio engine; screens do not own separate players | `apps/mobile/lib/features/player/player_controller.dart`, audio-engine adapter and player tests |
| Playback race handling | Request generations and serialized engine mutations protect against stale resolver results and overlapping prepare/play operations | PlayerController regression tests; execute latest CI suite |
| Queue progression | Completion advances the global queue; regression test verifies exactly one advance and no duplicate resolve | `player_controller_test.dart`; added in commit `c9372145cd3527ba98a109e9918a004e65475cbd`; latest CI run still pending at last audit |
| OS media session | Shared media-session bridge maps OS commands to the global player; platform adapters are configured for Android/iOS/macOS/Web/Linux/Windows | Code and platform dependencies exist; validate lock screen, notification, SMTC, MPRIS and Web Media Session on real targets |
| Mobile audio focus | Mobile interruption handling pauses on exclusive interruptions; route removal pauses to avoid headphone/Bluetooth speaker leakage | Adapter code and interruption regression test; device-level validation remains |
| Expired playback grants | Resume path can request a fresh grant rather than reusing an expired signed URL | PlayerController tests; verify provider expiry behavior against live authorized provider |
| Search | Search UI and metadata discovery exist; local recent-search behavior is present in the app implementation | Verify history persistence/error states and out-of-order response widget tests |
| Browse | Genre/discovery UI and backend metadata feeds exist | Curated editorial feeds, full charts and catalog-backed entity routes remain incomplete |
| Radio | Station directory and program/schedule metadata are exposed | Radio stream playback is not implemented; no station Play action should imply otherwise |
| Library | Favorites, playlists, history and download-related client/backend foundations exist | Complete account-switch, ownership, offline expiry/revocation and device storage tests before release |
| Provider rights | Provider capability and rights boundaries are documented; backend resolver is the authorization boundary | Production terms/territory evidence and live provider acceptance tests remain required |
| Cloudflare | API Worker typechecks and implements a narrow public metadata cache path | Worker deployment, domain/origin security, WAF/rate-limit setup and live cache tests remain |
| Capacity | Cloudflare/NestJS/Redis/PostgreSQL scaling architecture and staged load-test plan are documented | No one-million-user capacity claim until production-like load tests pass |

## Provider truth table

| Source | Metadata/discovery | Breezze native playback | Downloads | Current decision |
|---|---:|---:|---:|---|
| Audius official API | Yes | Yes, public ungated and API-accessible tracks only | No | First official third-party playback adapter; gated/restricted tracks are rejected |
| YouTube Music via `ytmusicapi` | Best-effort metadata only | No | No | Unofficial discovery adapter; never extract audio streams |
| Apple RSS / iTunes catalog | Yes, where the feed/API is available | No full-track playback grant | No | Metadata/chart/release/catalog discovery only |
| MusicAPI Core | Not connected | No | No | Future candidate only; credentials, plan and terms review required |
| Breezze-owned/licensed catalog | Internal metadata | Only with explicit rights record and approved delivery | Only with explicit download rights | Not a substitute for third-party licenses |
| User local files | Local metadata | Yes, on supported platforms | Already local | User-controlled local playback |

A metadata match, preview URL, video result, public endpoint or technically reachable stream is not proof of full-track playback rights. Provider health is not authorization. Failover must preserve recording identity, territory and permitted action.

## Current CI snapshot

Latest commit at this audit: `c9372145cd3527ba98a109e9918a004e65475cbd`.  
Latest workflow: [44986131001](https://github.com/MetroKim/MetroMusic/actions/runs/44986131001).

At the last observed check:
- Flutter analysis completed successfully.
- Flutter tests were still running.
- Backend/Prisma validation, tests and build completed successfully.
- Both Cloudflare Worker typechecks completed successfully.
- Linux/Android/Web, Windows, macOS and iOS build jobs were still running or pending.

Do not describe the complete workflow as green until every job for this exact commit has completed successfully. A later commit requires a new CI result.

## Release blockers / unfinished work

### P0 — Playback correctness and platform certification
- [ ] Complete latest CI run and fix any failures.
- [ ] Verify audio-service queue index/current item synchronization, including next/previous, repeat and shuffle.
- [ ] Test Android foreground playback, notification controls, lock-screen controls, audio focus and route changes on physical devices.
- [ ] Test iOS background mode, lock-screen controls, interruption handling and Bluetooth routes on physical devices.
- [ ] Test Windows SMTC, Linux MPRIS, macOS Now Playing and Web Media Session on their supported environments.
- [ ] Validate provider grant expiry, refresh, network loss, retry budget and typed error recovery with an authorized live source.
- [ ] Confirm there is no second player instance after navigation, sign-in/sign-out or app lifecycle transitions.

### P1 — Catalog, discovery and library
- [ ] Complete typed catalog search for tracks, artists, albums, playlists and music videos with source attribution.
- [ ] Complete album/artist/playlist listener detail routes from canonical catalog data.
- [ ] Connect real, territory-aware editorial and chart feeds; do not synthesize charts from search results.
- [ ] Complete library account-isolation tests for favorites, playlists, history and downloads.
- [ ] Complete offline lease expiry, online revalidation, takedown and account-switch tests.
- [ ] Add empty, loading, offline, provider-error and populated states for every screen.

### P1 — Provider and rights readiness
- [ ] Record provider-specific terms, allowed use, territories, attribution, caching and takedown obligations.
- [ ] Verify Audius playback eligibility and gated/restricted rejection against live API responses.
- [ ] Keep YouTube Music metadata-only unless a separately approved official playback path is implemented.
- [ ] Do not enable a provider until same-recording matching, rights checks, grant expiry and source validation pass.
- [ ] Add provider health, bounded retries, concurrency budgets and circuit-breaker tests.

### P2 — Production and scale
- [ ] Configure Cloudflare zone, TLS Full (strict), origin protection, WAF and route-specific rate limits.
- [ ] Deploy the API Worker and verify only explicitly public metadata is cacheable.
- [ ] Verify secrets, database backups, restore drills, migrations, alerting and incident runbooks.
- [ ] Complete tenant-isolation integration tests across every user-owned endpoint.
- [ ] Complete accessibility, reduced-motion, localization and responsive layout audits.
- [ ] Run staged load tests and publish measured results; do not claim one million concurrent listeners based on architecture alone.

## Explicitly not part of this release

- Artist portal, artist upload/claim tools or artist management dashboard.
- Subscription, membership, billing, payment, premium tier or paywall.
- Unofficial YouTube audio extraction, stream URL scraping, cookie reuse or access-control bypass.
- Generic third-party audio proxying or R2 re-hosting.
- Radio stream playback until an authorized station playback contract is implemented.
- A claim that every Apple Music/Spotify catalog recording is available in Breezze.

## Change-control rule

Update this register when a feature changes status. Link the implementation path and passing test/CI evidence. If rights approval, deployment, or physical-device verification is missing, keep the release gate open even when the code exists.
