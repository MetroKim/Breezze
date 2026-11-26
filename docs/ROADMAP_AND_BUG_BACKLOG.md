> **AUTHORITATIVE CURRENT PLAN — 26 Nov 2026:** Use [Breezze Master Plan v7](BREEZZE_MASTER_PLAN_V7.md) for the six-platform Flutter target, Linux distro qualification, current CI status and ordered remaining work. Everything below is a **historical backlog**; old Spotify/Deezer/Audius, five-tab, authentication and passing-test statements must not be treated as present-day approval or evidence. The [source no-release freeze](security/BREEZZE_RELEASE_FREEZE_20261125.md) remains active.

# Breezze Engineering Backlog — Completion Plan & Critical Defect Register

> **Current-release override — 2026-11-22:** This backlog contains older implementation snapshots. The current product and provider decisions are defined by [the gap register](audit/gap-register.md), [the multi-source provider architecture](architecture/BREEZZE_MULTISOURCE_PROVIDER_ARCHITECTURE.md), and [the third-party code policy](legal/BREEZZE_THIRD_PARTY_CODE_POLICY.md). Breezze's current release is listener-only: no artist portal, artist upload workflow, subscription, billing, membership or paywall. BitChord is an architectural reference only (GPL-3.0); do not copy its code, assets, tests or private endpoints. YouTube Music via `ytmusicapi` is metadata/discovery only, not an audio source. Audius is the first official third-party playback adapter and is limited to public, ungated, API-accessible tracks. Historical references below to BitChord parsers/adapters, YouTube Explode playback, Liner fallback, membership tiers or artist tooling are not current implementation approval and must not be used to reintroduce those paths.

## Current implementation status — 21 November 2026

This snapshot reflects source commit `f91932317315` and GitHub Actions run
[44911197349](https://github.com/MetroKim/MetroMusic/actions/runs/44911197349).
The complete Breezze quality workflow passed on that commit.

### Implemented on this branch
- [x] One root-owned Riverpod container and app-owned audio engine; shell rebuilds do not create duplicate containers.
- [x] Playback request generations, serialized engine operations, stale resolver protection, stop/sign-out invalidation and surfaced resolver/engine failures.
- [x] Native seek failures transition the player to a failed state; regression test added.
- [x] Listening-time scrobble ticks are driven by actual position-stream events while playing; pending sessions close on stop, track change, detach, disposal, end-of-track and playback failures.
- [x] Downloads library refreshes when the authenticated account changes; stale account results are discarded.
- [x] Persistent search history with deduplication, remove/clear, serialized concurrent writes and stale-response protection.
- [x] Browse metadata discovery and Radio station/program directory; radio playback is not fabricated.
- [x] Queue shuffle traversal retains the current item; repeat-one and shuffle regression tests added.
- [x] BitChord search parser correctly extracts nested title, artist and duration metadata.
- [x] YouTube Explode 3.1 API drift fixed; API-client provider result types are generic.
- [x] Mobile playback resolves canonical catalog IDs and uses authenticated backend rights authorization; YouTube and BitChord adapters are metadata-only.
- [x] Preview-only rights cannot issue full-stream URLs; preview grant windows are validated.
- [x] Downloads require backend authorization; preview grants cannot authorize downloads.
- [x] Downloaded files are stored in per-account app-private directories; metadata records owner, canonical catalog ID and rights end time.
- [x] Downloads list filters by account owner; legacy ownerless files are hidden rather than exposed to another session.
- [x] Offline playback uses a local-file source and bypasses the network resolver; expired download licences are blocked locally.
- [x] Download storage keys are sanitized; incomplete assets and malformed metadata are excluded from the library.
- [x] Catalog write/convergence endpoint requires JWT; external ID convergence uses an upsert to avoid duplicate-create races.
- [x] Production media signing requires a strong key and HTTPS CDN; signature verification uses constant-time comparison.
- [x] Signed playback/download URL lifetime is capped by the rights end time; download records retain the rights expiry.
- [x] Radio controller delegates through RadioService; public station/program DTOs omit raw `streamUrl`; mobile station requests have timeouts and stale-response protection.
- [x] CI runs Drift codegen, Flutter app analysis/tests, API-client analysis/tests, design-system analysis, audio-contract analysis/tests, Prisma generation/validation, backend typecheck/tests/build.

### Verification status
- [x] Complete CI run `44911197349` passed on source commit `f91932317315`.
- [x] Mobile app: dependency resolution, Drift generation, analyzer and tests passed.
- [x] API client: dependency resolution, analyzer and tests passed, including offline-download ownership/rights metadata tests.
- [x] Design system: dependency resolution and analyzer passed.
- [x] Audio contracts: dependency resolution, analyzer and tests passed.
- [x] Backend: Prisma generation/validation, TypeScript typecheck, Jest tests and Nest production build passed.
- [ ] Repeat full CI after any subsequent source change; a green run applies only to the commit it tested.

### Remaining release blockers
- [x] Add Cloudflare R2 private object storage, a signed-upload/playback Worker gateway, byte-range reads, and an R2-backed quarantine/transcode staging path. Worker/API code is covered by CI; deployment, custom domain, R2 bucket/token provisioning, and live end-to-end validation remain operator tasks. Processed assets remain staged and are not playable until a moderated catalog publication maps them to canonical track IDs and rights grants.
- [ ] Offline playback enforces stored owner and known rights expiry, but a device that remains fully offline cannot learn about a later takedown or rights revocation. Define a bounded offline licence lease and mandatory revalidation before the next online session.
- [ ] Add device-level tests for local file playback, corrupted/missing assets, account switching during active downloads, and expired licence behavior.
- [ ] Complete PlayerController lifecycle tests for engine detach/disposal, next/previous during pending loads, and scrobble tick/stop integration.
- [ ] Add mobile radio request/widget tests and a station timezone contract. The current schema has no station timezone.
- [ ] Add a real radio playback session contract only after stream rights, secure URL resolution, buffering/reconnect behavior and engine integration are designed.
- [ ] No Prisma migration directory/history is present. Establish a safe baseline/migration strategy against the actual deployed database before deployment.
- [x] Remediate the reported npm dependency vulnerabilities: upgrade the backend to patched NestJS 11.2.11 packages, update related Nest integrations, pin patched `glob`/`minimatch` overrides, and upgrade Wrangler to 4.166.0 with matching Cloudflare Worker types. Latest CI `npm audit` reports **0 backend vulnerabilities and 0 Worker vulnerabilities**.
- [ ] Verify repeated-play semantics for `RecentlyPlayed` against deployed data before changing its current `@@unique([userId, trackId])` constraint.
- [ ] Finish full artist/album/playlist detail routes, catalog-backed editorial feeds, account-isolation integration tests, accessibility/responsive checks and real-device audio validation.

**Working branch:** `feature/breezze-product-experience`  
**Target base:** `breezze`  
**PR:** [#6](https://github.com/MetroKim/MetroMusic/pull/6) (draft; not merged)  
**Status:** Active engineering backlog. Items are not complete until implementation, automated tests, and runtime verification are recorded.  
**Rule:** Do not mark a screen or capability as shipped merely because a UI exists.

This backlog is intentionally opinionated: stabilize the app and playback first, prove the current integrations, then finish the missing product surfaces. Breezze remains a free product with its own identity. No fabricated catalogue content, fake charts, fake radio playback, subscription prompts, or unlicensed media extraction.

---

## 0. Release gates — do these before expanding features

- [x] **P0 — Make the app container lifecycle stable.** Move `ProviderContainer` creation out of `BreezzeShell.build()` into a lifecycle owner (or use a single root `ProviderScope` with the required overrides). Dispose it exactly once. Attach the audio engine once, detach/dispose subscriptions and engine on teardown, and ensure onboarding/auth transitions do not create duplicate playback engines.
- [x] **P0 — Make playback requests race-safe.** Add a monotonically increasing playback request token/cancellation strategy. A resolver response may prepare/play only if it still belongs to the latest requested track. Invalidate older requests on track change, stop, logout, and engine detach.
- [x] **P0 — Repair playback state-machine transitions.** A new `StartRequested` must be legal from every active state (playing, paused, loading, buffering, seeking, interrupted, offline as appropriate). Define explicit cancellation of the previous load. Never let a stale `SourceResolved` transition a newer request.
- [x] **P0 — Handle playback failures honestly.** Catch resolver and engine exceptions; dispatch a failure state; expose retry/error details; do not leave the UI stuck in resolving/loading/buffering. Do not report a scrobble/listening event as a successful play before playback actually starts.
- [ ] **P0 — Complete playback controller tests.** Existing race/failure tests are in place; pause/resume during resolution, next/previous during load, engine detach and lifecycle widget coverage remain. Cover rapid A→B selection, A resolving after B, resolver returning null, resolver throwing, engine prepare throwing, play/pause during resolution, next/previous during load, engine detach, and queue boundary behavior.
- [ ] **P0 — Run and fix the complete validation suite.** Flutter dependency resolution, analyzer, all mobile tests, audio-contract tests, API-client tests, backend typecheck, backend tests, Prisma validation/generation, and production build. Record actual command output; never write “passed” without running it.
- [x] **P0 — Establish CI for the actual Breezze branch.** Full green validation is still required before release. Current `.github/workflows/ci.yml` only builds Gradle and its push branches are `main` and `develop`; it does not validate this Flutter/NestJS product branch. Add branch-aware Flutter + backend jobs, database migration validation, and required checks. Verify the workflow triggers on PRs targeting `breezze`.

## 1. Critical defects and suspicious behavior found during repository inspection

Severity key: **P0** blocks reliable release; **P1** can break a core feature or data integrity; **P2** degrades UX/maintainability. “Confirmed” means directly visible in the inspected branch code; “verify” means the risk needs runtime or migration evidence before changing behavior.

| ID | Severity | Finding | Evidence / impact | Required fix and proof |
|---|---|---|---|---|
| BUG-001 | P0 · Fixed in branch; lifecycle widget proof pending | Riverpod container is created inside the shell's `build()` | `apps/mobile/lib/widgets/bz_shell.dart` constructs `ProviderContainer`, attaches an engine and starts migration during widget build. A rebuild can create another container/engine and orphan the old one. | Move ownership to a stable lifecycle; add a widget test proving one container/engine across rebuilds and correct disposal. |
| BUG-002 | P0 · Fixed in branch; broaden controller coverage pending | Concurrent playback resolutions are not versioned/cancelled | `PlayerController._resolveAndPlay` awaits resolver and engine calls without checking whether the selected track changed. A late response can prepare/play an obsolete track. | Request generation + cancellation; deterministic fake-resolver tests with out-of-order completion. |
| BUG-003 | P0 · Fixed in branch; exhaustive transition proof pending | Starting a new track from several active states is not represented | `PlaybackStateMachine` handles `StartRequested` in idle, ended, failed and offline, but not playing, paused, loading, buffering or seeking. Controller dispatches it on every new selection. | Define transition table and cancellation semantics; exhaustive transition tests. |
| BUG-004 | P1 · Fixed in branch; storage-failure widget test pending | Search-history persistence failure is conflated with source/network failure | `SearchScreen._search` awaits `_history.add()` inside the same try/catch as provider search. A disk write error returns “Could not reach the music source” even if source search was never attempted. | Make history best-effort and independently report storage errors; test source search still runs when history storage fails. |
| BUG-005 | P1 · Confirmed missing behavior | Radio is a directory, not a playable radio product | `radio_screen.dart` displays station metadata/schedules and explicitly says playback is not integrated. | Define a radio playback contract/session type, resolve authorized stream URL server-side, support buffering/reconnect/stop/metadata, and add engine + API tests. Keep play controls hidden until complete. |
| BUG-006 | P1 · Verify migration/schema drift | RecentlyPlayed uniqueness may still prevent multiple plays of the same track | The inspected `backend/api/prisma/schema.prisma` still declares `@@unique([userId, trackId])`, while an earlier PR description says this uniqueness was removed to preserve play order. | Inspect the active `breezze` migration history and deployed DB before editing. Reconcile schema, migrations, generated Prisma client, and recent-history service. Test repeated plays create separate events and Home deduplicates for display. |
| BUG-007 | P1 · Confirmed integration risk | Radio screen bypasses the shared API client | `RadioScreen` uses raw `http.get` with no timeout/client lifecycle and no typed response model. Errors are collapsed into one generic message. | Move radio calls into `breezze_api_client` repository; add timeout, typed DTO parsing, retry policy, and API-client tests. |
| BUG-008 | P1 · Fixed in branch; mobile request tests pending | Radio station list requests can overlap | `_loadStations` has no request generation/disposal cancellation. A retry or refresh can race an earlier request. | Add request token/cancellation and tests for stale responses. |
| BUG-009 | P1 · Timeout fixed; station timezone contract still missing | Radio schedule request is not bounded by a timeout and schedule UI lacks explicit timezone context | `_loadPrograms` performs raw HTTP and renders `airsAt.toLocal()` without stating the station timezone. | Add timeout, server-defined timezone field, timezone-aware display, and tests around UTC/local conversion and daylight-saving boundaries. |
| BUG-010 | P1 · Fixed in branch; CI verification pending | Radio controller and service appear to duplicate station-query logic | Both `backend/api/src/radio/radio.controller.ts` and `radio.service.ts` implement station listing/detail/program queries. | Inspect module wiring; keep one service-backed controller path and add controller/service tests. Avoid two competing implementations. |
| BUG-011 | P1 · Fixed in branch; CI verification pending | Station list query returns full Prisma records, including `streamUrl` | `RadioController.stations()` returns `radioStation.findMany()` without a select/DTO. Stream URL exposure may be intentional for public streams, but must not expose private/signed/expiring URLs. | Define public station DTO. Return only safe public metadata; issue short-lived playback URLs through an authorized resolve endpoint if required. |
| BUG-012 | P2 · Confirmed robustness gap | Search history writes are not serialized | Concurrent `add/remove/clear` operations each load then overwrite the same JSON file; fast actions can lose an update. | Serialize writes or move search history into existing Drift database; add concurrent-operation tests. |
| BUG-013 | P2 · Confirmed validation gap | Search-history tests are not sufficient for storage failure/concurrency | Current tests cover order, dedupe, cap, remove, clear and malformed JSON only. | Add file I/O failure, concurrent adds, concurrent clear/remove, whitespace and Unicode cases. |
| BUG-014 | P2 · Confirmed UX gap | Radio station cards have no artwork and use a generic Material radio icon | Current UI has no station artwork field in its local model. | Add optional station artwork to API DTO and render real image with an accessible fallback; no fake station art. |
| BUG-015 | P2 · Confirmed navigation gap to verify | Main tab bar is horizontally scrollable; small-screen and wide-layout behavior needs proof | Current shell has seven destinations. Search shortcut index was updated, but layout/semantics need device coverage. | Test narrow phones, tablets, keyboard navigation, selected tab semantics and mini-player overlap. |

### Validation status

GitHub Actions now runs Flutter analysis/tests, NestJS/Prisma validation, and Cloudflare Worker typechecking for pull requests targeting `breezze`. Full workflow `44913618622` passed all three jobs on source commit `9cc102e2143fce884569ecc327411374f873214d`.

---

## 2. Product completion roadmap

### Phase A — Stabilize the foundation (P0)

- [x] Fix BUG-001 through BUG-003 in source; tests added but not executed.
- [x] Fix BUG-004 in source; widget test still pending.
- [ ] Run Flutter analyzer/tests and add app-root lifecycle tests before closing Phase A.
- [ ] Verify app startup, auth gate, onboarding, sign-out, and re-login do not leak providers, engines, subscriptions, or stale user state.
- [ ] Verify the audio engine lifecycle on Android, iOS, desktop and web targets that the project actually supports. Do not claim an OS is supported until its plugin/runtime path is tested.
- [ ] Define one typed error model across API client, provider adapter, playback resolver, and UI.
- [ ] Add request timeouts, cancellation, retry/backoff rules and offline behavior to network repositories.
- [ ] Add structured, privacy-safe diagnostics. Never log access tokens, signed stream URLs, private user data or full sensitive request bodies.
- [ ] Add crash-safe persistence and migrations for local Drift stores; test upgrade from the previous schema.
- [ ] Add integration smoke tests for app launch → sign in → search → play → pause → next → favorite → restart.

**Exit gate:** no known P0 issue, analyzer clean, tests green, no duplicate playback engine, and rapid track switching is deterministic.

### Phase B — Complete catalog discovery (P1)

- [ ] Build a typed Catalog/Search repository rather than calling provider adapters directly from screens.
- [ ] Expand search beyond tracks: artists, albums, playlists, videos and stations where the connected provider/API actually supports each type.
- [ ] Add artist detail pages with biography, artwork, releases, popular tracks and related artists from real catalog data.
- [ ] Add album detail pages with release metadata, ordered tracks, play-all/shuffle and save actions.
- [ ] Add playlist detail pages with ownership, ordered membership, collaborative rules only if supported, and safe empty/error states.
- [ ] Add genre/mood browse landing pages using real catalogue or editorial feeds. Current genre query results are discovery results, not charts.
- [ ] Add verified charts, new releases and editorial collections only after backend/provider contracts and territory/rights filters exist.
- [ ] Add pagination/infinite scroll, caching, request dedupe and pull-to-refresh.
- [ ] Add deep links for artist, album, playlist, track and station entities.

**Exit gate:** every detail route opens a canonical entity, every action works, and no screen fabricates metadata or editorial ranking.

### Phase C — Make Library real and durable (P1)

- [ ] Audit Favorites, Playlists, Recently Played, Downloads and Library sections against backend ownership and local persistence.
- [ ] Separate favorites from downloads in both data model and UI.
- [ ] Complete playlist create/rename/delete/reorder/add/remove flows and enforce server-side owner checks.
- [ ] Add optimistic UI with rollback and an offline outbox for supported mutations.
- [ ] Verify multi-account behavior on one device: user A's private library must never appear for user B after sign-out/sign-in.
- [ ] Fix and migrate RecentlyPlayed behavior after BUG-006 verification.
- [ ] Add local DB migration tests, sync conflict tests and account-switch isolation tests.

**Exit gate:** restart/offline/account-switch scenarios preserve correct user data and do not leak data across accounts.

### Phase D — Complete listening experience (P1)

- [ ] Finish Now Playing: queue view/edit/reorder/remove, shuffle, repeat modes, seek, elapsed/remaining time, loading/error states.
- [ ] Verify lock-screen controls, notification controls, audio focus, Bluetooth/headset events, interruptions, background/foreground transitions and app termination recovery.
- [ ] Add lyrics provider matching, attribution, language handling and explicit unavailable state. Do not invent synced timing.
- [ ] Implement radio playback only after the stream/session contract, rights, and engine behavior are approved.
- [ ] Radio: station artwork, schedule timezone, current show, reconnect/backoff, network-loss recovery and background playback.
- [ ] Add output-route/device selection only on platforms where supported.
- [ ] Verify playback quality and codec behavior on real devices and poor networks.
- [ ] Ensure downloads are actually authorized, encrypted or protected as appropriate, resumable, expiry-aware, and removed on logout if required by rights policy.

**Exit gate:** uninterrupted catalog playback and authorized radio playback work on supported devices, including background and interruption scenarios.

### Phase E — Home, personalization and content integrity (P1/P2)

- [ ] Replace placeholder Home rails only with backend-backed user history, favorites, recommendations and editorial content.
- [ ] Define cold-start onboarding and preference capture; no empty fabricated “Made for You” sections.
- [ ] Add Recently Played, Replay and recommendations with explainable data provenance.
- [ ] Add recommendation feedback controls and privacy settings.
- [ ] Verify all rails respect territory, rights, explicit-content and takedown rules.
- [ ] Add loading skeletons, empty states, error recovery and cached/offline behavior to each rail.

### Phase F — Visual, accessibility and platform quality (P2)

- [ ] Audit every screen against the Breezze monochrome visual system and existing design tokens.
- [ ] Replace generic icons with the supplied/approved Breezze SVG icon set where available; no emoji iconography.
- [ ] Ensure glass/blur effects are limited to floating surfaces and do not reduce content readability.
- [ ] Add responsive tablet/desktop layouts and keyboard focus/shortcuts where supported.
- [ ] Add semantics labels, screen-reader order, 48dp minimum touch targets, contrast checks and reduced-motion behavior.
- [ ] Add localization infrastructure and timezone/locale formatting.
- [ ] Add image caching, bounded memory use, list virtualization and performance profiling.
- [ ] Run screenshot/golden tests for light and dark themes and common device sizes.

### Phase G — Backend, security, rights and operations (P0/P1)

- [ ] Verify authentication and authorization separately on every private endpoint.
- [ ] Audit tenant/user scoping for favorites, playlists, downloads, listening history, preferences, notifications, uploads and admin routes.
- [ ] Verify admin role grants/revokes are persisted and every admin endpoint is guarded.
- [ ] Verify playback resolution applies territory, rights window, takedown and attribution checks on every request.
- [ ] Ensure provider credentials and signing secrets remain server-side; mobile app must not ship private API keys.
- [ ] Add rate limits, abuse controls, request validation, pagination limits and safe error responses.
- [ ] Add database indexes for actual query patterns and review every uniqueness constraint against product semantics.
- [ ] Verify migrations from a clean database and from the previous deployed schema; never edit deployed migration history casually.
- [ ] Add backups, restore drills, observability, alerting, health/readiness checks and queue/worker monitoring.
- [ ] Add retention/deletion flows for account data and user privacy requests.
- [ ] Load-test search, catalog resolve, playback resolve, home, library and radio endpoints. Set measurable SLOs before scaling claims.

### Phase H — Release readiness (P0)

- [ ] Define supported platforms and minimum OS versions; test each supported target on real hardware.
- [ ] Verify clean install, upgrade install, logout/login, expired token, offline launch, poor network, low storage and interrupted download.
- [ ] Verify no crash loops, unhandled async errors, leaked streams/subscriptions or unbounded queues.
- [ ] Complete privacy policy, terms, source attribution, rights notices and app-store metadata.
- [ ] Complete accessibility, security, performance and rights reviews.
- [ ] Create a release checklist with owner, evidence, rollback plan and known limitations.
- [ ] Promote PR only after CI passes and all P0 blockers are closed. Merge only to the intended `breezze` base after review.

---

## 3. Regression test matrix

- [ ] **Playback:** A→B rapid selection; stale A resolver; resolver null/throw; engine prepare/play throw; pause while resolving; next at final queue item; previous at first item; shuffle/repeat; interruption; network loss; detach/dispose.
- [ ] **Search:** blank query; Unicode; rapid queries; stale result; no results; provider timeout; malformed provider payload; history file unavailable; corrupt history; concurrent add/remove/clear.
- [ ] **Browse:** change genre rapidly; stale genre result; source offline; no tracks; repeated retry; download progress; play selected item with correct queue context.
- [ ] **Radio:** empty directory; malformed station DTO; 401/403/404/500; timeout; duplicate refresh; deleted station while detail open; invalid schedule date; timezone formatting; stream URL privacy; reconnect behavior.
- [ ] **Library:** favorite add/remove; playlist ownership; reorder persistence; duplicate track; offline mutation; sync conflict; logout/login isolation.
- [ ] **Downloads:** permission denied; insufficient storage; interrupted transfer; expired rights; duplicate download; file missing; logout cleanup; corrupt file.
- [ ] **App lifecycle:** auth refresh; app background/foreground; process killed during playback; engine recreation; onboarding overlay; navigation rebuild; theme switch; orientation/resize.

---

## 4. Work order I will follow

1. Complete lifecycle/widget regression tests for the root ProviderScope and audio engine.
2. Execute the new deterministic playback tests, add remaining failure/detach coverage, and correct any analyzer/test failures.
3. Finish the remaining playback error paths and search-history failure-isolation test.
3. Reconcile RecentlyPlayed schema/migrations and verify backend history behavior.
4. Move Radio to a typed repository, harden its API contract, and define authorized radio playback.
5. Finish artist/album/playlist detail routes and real catalogue-backed Browse/Home feeds.
6. Complete Library persistence, downloads and account isolation.
7. Add full CI, platform regression coverage, accessibility and release gates.

**Definition of done:** code is implemented, tests exist and pass, API/data contracts are verified, user-visible states are complete, rights/security rules are enforced, and the gap register links to evidence. A checkbox stays open if any of those are missing.
