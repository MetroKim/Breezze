# Breezze — Unified Master Specification (v5 + v6 → one v6)

**Status:** Incremental adoption, not a claim of production readiness.  
**Target:** `MetroKim/Breezze`, default branch `main`.  
**Canonical version:** **Breezze Unified v6**. This is the **single authoritative v5+v6 integration and release roadmap**; older v5/v4 structural sketches and root outlines are historical. Preserve existing operational details and deployed data until migration acceptance. All feature statuses are evidence-gated, not source-file-count claims.  
**Product contract:** Free, no subscriptions/ads, four primary tabs: Home, Browse, Library, Search. One global player and mini-player.

**Provider capability clarification (25 November 2026):** Audius is retired. The supported external catalog providers are Deezer and unofficial YouTube Music (`ytmusicapi`). The YouTube Music adapter enables song/album/artist/playlist/mood/chart/video **discovery**, and separately exposes an authenticated **non-production experimental direct-audio candidate** flow behind a development-only flag. This updates older broad "metadata-only" descriptions, but does **not** enable production media `playback`/`download` grants or bypass any provider authorization. See `docs/architecture/YOUTUBE_MUSIC_PRIMARY_PROVIDER.md`.



### Unified v5 + v6 decisions (applies to every phase)

This specification merges the v5 module mapping and v6 feasibility roadmap into one execution contract. **No second scaffold is generated.** These decisions supersede conflicting examples in older drafts.

| Concern | One supported integration path | Rejected duplicate / premature assumption |
| --- | --- | --- |
| Flutter client | Existing `apps/mobile` Riverpod app and one player; Home/Browse/Library/Search + shared mini-player | Second `app/router`, second audio engine or a fifth Radio tab |
| Shared packages | Existing `breezze_api_client`, `breezze_audio_contracts`, `breezze_design_system` | Renaming packages to the unprefixed v5 examples; duplicating theme tokens in the app |
| Local persistence | Drift/SQLite and existing transactional sync outbox; secure storage for sensitive account-scoped cache | Adding Hive and Isar alongside Drift, or a second competing sync journal |
| Identity | Existing Supabase integration adapter plus legacy account mapping and safe fallback; complete Google/Apple signed-device setup before cutover | Deleting the live Prisma `User`/legacy auth tables or claiming Supabase Auth replaces all app-level authorization |
| API and database | NestJS + Prisma in `backend/api` on a Node-compatible host; existing Prisma-managed app tables, migration history and user IDs | Deploying NestJS/Prisma directly as a generic Cloudflare Worker; replacing migration history with `0001`–`0011` sketches |
| Edge and media | Existing Cloudflare `api-worker` proxy and `media-worker` for **app-owned or licensed assets**, authorized downloads, models and exports | Generic rehosting/caching of third-party music, public caching of account-bound stream grants |
| Content and playback | YT Music discovery plus an isolated, non-production opt-in direct-audio feasibility path; production playback remains provider-approved or Breezze-owned licensed media, resolved against listener, territory, expiry and rights | Using Deezer ARL/cookies to bypass access limits; claiming previews grant full-stream or offline rights |
| B-Quality, B-Upscale, B-Spatial | Extend existing audio contracts; optional audited ONNX/FFI modules **after** sample-rate, license, thermal, CPU and listening tests | Shipping NovaSR on every lossy 44.1/48-kHz stream; claiming synthetic super-resolution is genuine lossless/Hi-Res |
| B-Mix | Existing automix/crossfade contracts, then a verified native sample-accurate DSP scheduler | Parallel player and unchecked zero-latency Rust/Dart or SoLoud guarantees |
| On-device AI | One optional runtime abstraction with validated model checksums, size and platform capabilities; benchmark a **single** compatible engine first | Installing every `flutter_edge_ai` engine or asserting one package handles arbitrary audio DSP models on all OS targets |
| Edge inference | Evaluate supported Cloudflare Workers AI bindings and budgets for non-realtime tasks | Relying on unverified Constellation/ONNX custom deployment or promising sub-100-ms inference |
| B-Lyric | Existing LRCLIB path; add pronunciation, translation, licensing and source attribution behind opt-in settings | Assuming arbitrary lyric text can be translated, cached and redistributed without rights checks |
| B-Collect / B-Pin / B-Sync | Evolve existing playlist store, owner-scoped library APIs and outbox, with server-side ownership and offline replay tests | Second playlist codebase, blind device merge or unprotected public pin/realtime channels |
| B-Replay | Existing NestJS replay metrics; verify yearly aggregation, offline-safe view and export/share | Generating invented music statistics, unapproved emails or export jobs without retention policies |
| B-Concerts | Integrate into existing NestJS discovery/backend only after authorized event providers are available | Inventing tickets or substituting search snippets for an authoritative event catalogue |
| B-Social | Opt-in future milestone using authenticated Supabase Realtime Broadcast/Presence; persist changes with backend authorization and a Dart-compatible CRDT bridge | Importing JavaScript Yjs provider into Flutter; interpreting ephemeral Broadcast as durable playlist storage |
| API client | Evolve current typed transport and validate against OpenAPI before introducing automated generation | Blindly replacing the current client with a generated duplicate |
| Release | CI for exact `main`, web preview, Android/iOS simulator acceptance, approved media rights and real-device qualification | Calling builds, simulations or architecture diagrams proof of production audio quality |

### Unified execution ledger

The original v5 Phase 1–20 sequence and v6 Phase 7.5–7.11 **are folded into these stages**, not separate versions:

| Stage | Integrated requirements | Gate / current evidence |
| --- | --- | --- |
| U0 — Foundation | Monorepo cleanup, token ownership, auth ownership, CI, four tabs, canonical IDs and signed media contracts | Scaffold consolidated. CI builds verified on earlier commits; each new commit requires a fresh pass |
| U1 — Accounts | Native Google/Apple Supabase integration, safe legacy linking, token rotation, signed-identity migration, account/profile/settings | Source adapters exist; provider production signing and cross-device identity qualification **open** |
| U2 — Playback and downloads | One playback authority, authorized full-track streams, queue and interruption correctness, media session, expiry/renewal, licensed downloads and predictive prefetch | Code and automated tests exist; rights-certified, real-device playback and low-network performance **open** |
| U3 — Library and B-Collect | Favorites, playlist edits, bulk multi-playlist addition, saved albums and cross-device/outbox reconciliation | Multi-playlist CI, emulator and production smoke passed on previous main; any later changes must rerun |
| U4 — B-Pin | Pinned saved albums, pinned followed artists and playlist ordering; owner scope, offline journal, reliable UI | Album pin implementation in progress; artist/playlist pin ordering **open** |
| U5 — Playback quality and on-device AI | Optional runtime/model registry, checksum/download, NovaSR/FlashSR sample-rate experiments, Rust FFI, B-Mix/Demucs/HRTF | Design contracts only or partial primitives; **not implemented/benchmarked** as end-to-end DSP |
| U6 — Lyrics, Replay and concerts | Translation/pronunciation, replay annual rollups and exports, licensed event discovery, notification preferences | Replay and lyrics backend primitives exist; full feature acceptance **open** |
| U7 — Social and personalization | Safe local embeddings, recommendation feedback, authenticated Jam, collaborative playlist persistence and moderation | **Not implemented**; rights/access/cross-client tests required |
| U8 — Release certification | Accessibility/goldens, low-end thermal/soak, production alerts, backing up/restoring DB, signed binary, device and rights certification | **Open**; no blanket production-ready claim |

**Release rule:** No stage is complete until its individual implementation, automated tests, device/production acceptance where applicable, security/rights evidence and exact-commit CI pass. No empty folders, unused dependencies, unlicensed media proxies or fake performance claims are deliverables.

## 1. Inventory-based merge decisions

| ID | Decision | Reason / exact integration |
| --- | --- | --- |
| M01 | **Preserve** `apps/mobile` and existing Riverpod + player controller. | It already owns one playback authority. Do not create a second controller at `core/audio/player_controller.dart`. |
| M02 | **Preserve** existing package names `breezze_audio_contracts`, `breezze_api_client`, `breezze_design_system`. | Renaming to unprefixed names breaks imports. Evolve these packages in place. |
| M03 | **Preserve Drift/SQLite** and existing outbox tables. | Do not introduce both Hive and Isar without a measured requirement and a migration plan. |
| M04 | Keep **NestJS + Prisma** in `backend/api`, Node/container host. | Cloudflare `api-worker` remains a thin API edge proxy; do not assume NestJS + Prisma is deployable to the Worker runtime. |
| M05 | **Supabase** is the *target* for Auth, Realtime, and Postgres hosting. | Existing `User` model, auth API, Flutter session storage and foreign keys still operate on legacy IDs. Migrate with rollback; do not delete this live schema first. |
| M06 | Restrict Prisma ownership to application tables in `public`; Supabase owns `auth`. | Make an explicit schema/migration plan; the Prisma CLI `--schema` flag selects a **Prisma schema file**, not PostgreSQL namespace. |
| M07 | Supabase asymmetric JWTs use JWKS; backend verifies issuer, audience, signature, expiry and token type. | Client never receives service-role or signing secrets. Retain backend authorization and row ownership checks. |
| M08 | Keep current Cloudflare API proxy and limited public-metadata cache. | Do not add a second R2 proxy for unauthorized provider recordings; R2 is for app-owned/licensed media, models and user exports with access controls. |
| M09 | Keep direct authorized provider playback. | Deezer **preview** is not licensed full-track streaming; ARL/cookie extraction must not be used to bypass provider limits. YT Music is metadata only. SoundCloud requires an approved playback path. |
| M10 | Reuse `packages/audio_contracts/lib/src/automix.dart` and `audio_quality.dart`. | B-Mix and quality contract already exist. Extend instead of duplicating. Never describe enhanced lossy audio as lossless. |
| M11 | Add B-advanced DSP **behind capability/rights gates** and opt-in settings. | Neither ONNX model export nor sample-rate conversion guarantees audible improvement, battery budget or Hi-Res source fidelity. |
| M12 | Use optional on-device AI adapters. | `flutter_edge_ai` is a framework for text generation/embeddings; a generic audio DSP model still needs correct PCM/I/O, model architecture and inference integration. Do not add all plugins automatically. |
| M13 | **Do not use `@cloudflare/constellation` by default.** Use supported Workers AI model bindings when suitable. | Current Cloudflare documentation is centered on Workers AI. Arbitrary ONNX deployment is not assumed; custom models require verified access/support. |
| M14 | Keep Flutter `just_audio` as the baseline engine. | DSP bridging into `flutter_soloud` / Rust is an experimental adapter, not a wholesale engine swap. Prove gaplessness, background audio, interruption and output on each platform. |
| M15 | Use Supabase Realtime Broadcast + Presence for *future* B-Social experiments. | Flutter cannot import the JavaScript Yjs provider directly; choose a verified Dart CRDT strategy or a server bridge, persist snapshots and authorize channel membership. |
| M16 | Reuse existing replay, lyrics, recommendations and downloads modules. | Extend existing NestJS services rather than replacing them with proposed empty folder trees. |
| M17 | Avoid importing BitChord GPL code or app assets into proprietary Breezze. | Architectural references only; audit all third-party licenses before distribution. |
| M18 | Add `*.onnx` to Git ignore; model artifacts are fetched on demand by hash. | Verify integrity and redistribution rights and offer a clean disabled fallback. |

## 2. v6 module homes — relative to *real* source

| Feature | Keep / extend | New component only after gate |
| --- | --- | --- |
| B-Lossless | `packages/audio_contracts/lib/src/audio_quality.dart`; `core/audio` adapters | Native FLAC/ALAC capability probe, verified output formats |
| B-Upscale | `packages/audio_contracts/lib/src/b_audio_processing_policy.dart` | `apps/mobile/lib/core/audio/effects/upscale/` with local model registry and DSP adapter |
| B-Spatial | Existing player + audio adapters | `apps/mobile/lib/core/audio/effects/spatial/` with tested HRTF and safe latency budget |
| B-Mix | `packages/audio_contracts/lib/src/automix.dart` and crossfade | Real beat/key analysis, native scheduler, per-engine latency tests |
| B-Lyric | Existing lyrics feature and backend | Translation/pronunciation adapters with licensing and per-user cache |
| B-Replay | Existing `backend/api/src/replay/` | Long-term rollups and verified export UI |
| B-Collect / B-Pin | Existing library/playlists | Account-scoped bulk writes, ordered pin table, conflict tests |
| B-Offline / B-Sync | Existing Drift outbox/download logic | Realtime notifications and rights-aware sync reconciliation |
| B-Concerts | Listener-facing catalog feature | Aggregation service, official API availability and territory-aware linking |
| B-Social | Future feature flag only | Realtime room lifecycle, moderation, playlist CRDT persistence |
| On-device semantic search | Existing search feature | Downloadable embeddings, local vector index, consent/device support |

**Do not create identical `core/theme` and `packages/design_system/src/theme` implementations.** The shared package remains the single design-token owner. Keep listener-facing navigation to **four tabs**, regardless of outdated Radio references in older documents.

## 3. Feasibility and truth-in-labeling gates

1. **Baseline audio:** verify the current single player/queue, grant refresh and interruption behavior on Android/iOS/desktop first.
2. **AI framework:** evaluate exact package versions and platform architecture. Load only the needed engine. A passing package build does not prove local inference or quality.
3. **NovaSR:** 52 KB refers to published model size, not a complete runtime. Published model is for **16 kHz input**; never apply to arbitrary 44.1/48 kHz streams without an explicit resampling policy and perceptual AB test.
4. **FlashSR:** published ONNX variant is small, but the advertised benchmark is not a guarantee on Snapdragon 6-series; profile real device, RAM, thermal throttling, model warm-up and complete PCM processing.
5. **Demucs:** test a single compatible ONNX graph and realistic 4-minute track; mobile acceleration and battery cost remain unverified. Do not bundle 4-stem assets into every install.
6. **Rust/FFI:** prioritize glitch-free callback processing over a `<=3 ms` Dart round-trip headline; the real-time audio callback must never allocate or call Dart. Instrument underruns and p95/p99 processing time.
7. **Edge inference:** Workers AI is *catalog/availability/budget-gated*. Model exportability does not mean Cloudflare will host the model. Cloud-hosted translation must enforce lyric copyright, API rates and privacy.
8. **Social:** authenticate each room and collaborator, persist authoritative queue/playlist changes, test reconnects, clock drift and account isolation.
9. **Reliability:** benchmark real hardware/emulators, capture artifact SHA and source revision, run Flutter/Prisma/Worker checks on exact main commit.
10. **Claims:** B-Spatial cannot be described as superior to Dolby Atmos, or B-Upscale as lossless, without independent listening and engineering evidence.

## 4. Implementation sequence (existing features first)

| Stage | What is merged | Exit gate |
| --- | --- | --- |
| V6-0 | Mainline audit, dependency and model feasibility decisions, new processing contracts | No regressions in Flutter + backend CI; no duplicate architectures |
| V6-1 | Supabase auth adapter behind opt-in configuration and matching Breezze login UI | Existing accounts and sessions migrate safely; two-account isolation tests; rollback |
| V6-2 | Four-tab shell audit, playback/rights and download regression verification | Full queue and grant lifecycle works on emulator + supported host |
| V6-3 | Model registry, checksummed optional downloads, device/battery capability detection | Unsupported devices fail closed, app builds without models |
| V6-4 | One B-Upscale implementation and tests | Benchmark + blind A/B evidence; no inaccurate lossless labeling |
| V6-5 | B-Mix native scheduling and optional B-Spatial proof of concept | Soak tests, no audible glitches, thermal/battery budgets |
| V6-6 | Replay, pinned items, multi-select, sync and translation | Backend ownership and offline reconciliation tests |
| V6-7 | Concert aggregation + opt-in social | Authorized provider access; 10-client room tests and reconnection |
| V6-8 | Final accessibility/security/rights/release certification | Signed builds, live rights grants, device qualification, rollback drills |

## 5. What this merge does **not** assert

- That `flutter_edge_ai`, NovaSR, FlashSR, Demucs or Rust audio callbacks have already been integrated into Flutter playback.
- That Supabase Auth migration, JWT verification, Prisma migration or row-level security has been executed.
- That a Deezer ARL or SoundCloud track is automatically licensed for full Breezze streaming.
- That Workers AI can run arbitrary uploaded ONNX models or deliver 100 ms edge inference.
- That main builds pass until CI finishes against the exact commit.

## 6. References / upstream capability checks

- Flutter Edge AI: https://pub.dev/packages/flutter_edge_ai and https://flutteredge.ai/docs/installation
- Current SoLoud custom DSP: https://pub.dev/packages/flutter_soloud
- NovaSR: https://github.com/ysharma3501/NovaSR
- FlashSR: https://github.com/ysharma3501/FlashSR
- Cloudflare Workers AI: https://developers.cloudflare.com/workers-ai/
- Supabase JWT signing: https://supabase.com/docs/guides/auth/signing-keys
- Supabase Prisma: https://supabase.com/docs/guides/database/prisma
- Existing release blockers: `docs/audit/gap-register.md`

This is the **mainline migration contract**, not a second pretend repository tree. Each new directory must contain implemented, tested code before it is listed as complete.


## 7. Native social sign-in implementation (Feature 2)

The Flutter login screen now calls the **existing** `AuthSessionController.socialLogin()`.
With Supabase enabled, it uses native Google (Android/iOS) or Apple (iOS);
in legacy mode, the old provider flow remains for rollback. No extra login
page, auth provider, or browser fallback was added.

**Runtime activation requires all three independent layers:**

1. Flutter `--dart-define=BREEZZE_SUPABASE_URL=...` and
   `BREEZZE_SUPABASE_PUBLISHABLE_KEY=...`. These are public client
   configuration values; NEVER ship service-role keys.
2. Backend `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`; the verified
   exchange endpoint remains inactive until both are present.
3. Google/Apple identity-provider registration and mobile platform signing:
   - Google Android: configure Android OAuth app ID/package and both debug
     and release SHA certificate fingerprints in Google Cloud, plus the
     Web/server OAuth client registered with Supabase. Pass
     `BREEZZE_GOOGLE_WEB_CLIENT_ID` to the Flutter build.
   - Google iOS: register its bundle ID and iOS OAuth client in Google Cloud;
     pass `BREEZZE_GOOGLE_IOS_CLIENT_ID` to the Flutter build **and**
     to `tool/generate_platform_targets.sh` as an environment variable so
     it installs the reversed client ID URL scheme in generated Info.plist.
   - Apple iOS: register Breezze's exact bundle ID under Apple Developer,
     enable the **Sign in with Apple** capability in Apple Developer and the
     Runner provisioning profile/entitlements, then add that App ID to the
     Supabase Apple Auth provider. Only after the native capability is signed
     and verified should the Flutter build set
     `--dart-define=BREEZZE_APPLE_NATIVE_ENABLED=true`.
     This intentionally does not enable browser-based Apple OAuth.

**Fail-closed behavior:** No configured provider means no native button.
Cancelled system authorization does not create a Breezze session. Token
verification or account-mapping failures clear the transient local Supabase
session. Existing account email matches require **explicit** legacy account
ownership verification; no automatic linking. Cross-platform desktop/web
native Google/Apple support is a separate gated feature; email login remains
available.

**Device certification remains open:** Verify Google on real Android/iOS
signing identities, Apple on an Apple Developer-provisioned iOS build, and
cross-account legacy data isolation. Emulator/source builds alone do not
prove that an OAuth provider has been configured or that the system sheet
can successfully issue a token.

## 8. Explicit legacy account linking (Feature 3)

When Supabase verifies an identity but its email already belongs to an older
Breezze account, the exchange route raises `LEGACY_ACCOUNT_LINK_REQUIRED`.
Flutter keeps the verified Supabase session and shows an account-linking card
inside the **existing** login screen. The listener must supply the old Breezze
email and old Breezze password. The backend verifies that Argon2 hash independently
of Supabase's signed-in identity, and stores a single `SocialAuthIdentity`
mapping to the **existing** `User.id`. No playlist/library/media rows are
copied, merged, reassigned, or deleted.

The link route `POST /api/v1/auth/supabase/link-legacy` is rate limited by
the same per-account Redis window as password login. PostgreSQL serializable
transactions reject identity collisions, duplicate subjects, and simultaneous
conflicting claims. Admin/MFA accounts and older social-only accounts with
non-user-known passwords are intentionally excluded until additional identity
verification is available. An unchanged existing mapping is idempotent; a
mapping owned by another user is never overwritten.

A failed old password is not logged or stored. Cancel clears the temporary
Supabase session. The legacy authentication implementation remains temporarily
available for rollback; removal happens only after migrations and per-user
authorization checks pass in production.


### Different-email identity migration (Apple private relay)

Before their first Supabase sign-in, returning Breezze users may select
**I already have a Breezze library** in the existing sign-in panel. That
choice is persisted in platform-secure storage so a relaunch cannot quietly
create a new account before linking. After Supabase verifies any Google,
Apple, or email identity, Breezze opens the old-account proof step *before*
issuing a Breezze API session. The user supplies their original account
email and password separately, regardless of the identity provider's
current email. Clearing/canceling migration locally clears the pending
choice. Privileged/MFA and legacy social-only identities still need a more
specialized high-assurance migration process; no identity is linked by
matching an email or copying a row.


### Supabase session renewal boundary

Mapped Breezze API access JWTs are valid for at most 15 minutes and
remain revocable via an owner-scoped token-family row. Families issued
after **verified Supabase identity exchange** carry a distinct `sb:`
prefix and expire after 16 minutes. The legacy `POST /auth/refresh`
endpoint explicitly rejects those families (`SUPABASE_REFRESH_REQUIRED`);
only another independently verified Supabase session can obtain a fresh
Breezze API token through `POST /auth/supabase/exchange`.

This keeps a stolen transitional Breezze refresh token from extending
access independently for 30 days after a Supabase session is revoked.
Legacy password/social sessions retain their existing rotation scheme.
The family marker and short expiration require no schema migration.


## 9. Cross-device playlist synchronization (Feature 5)

The existing `PlaylistStore` remains the local playback/metadata cache.
Its `playlists.json` now uses one atomic envelope holding both the playlists
and an ordered `pending` edit journal. Legacy list-only files are supported.
Creates, renames, deletes, song additions, removals, and reorders write the
local state and retry intent to the same temp-file/rename transaction, so
offline edits are durable across app restarts. Guest playlists remain local.

The API accepts optional validated **v4 client UUIDs** on playlist create,
replays an already-owned UUID idempotently without overwriting subsequent
renames, and rejects attempts to claim another account's UUID. The owner-
filtered playlist list includes ordered canonical track metadata, restoring
full playlists on a second device instead of only titles.

On sign-in/Library refresh, Breezze attempts strict-order replay via the
existing authenticated endpoints, resolving external track IDs through the
canonical catalog first. The source-to-catalog mapping is cached in Drift.
A network failure, permission denial, or concurrent reorder membership
conflict **keeps the operation pending**. A cloud snapshot never overwrites
a playlist with pending local edits, while remote deletion is respected
after the journal drains. Auth-token or account changes abort further replay
and prevent acknowledgement of the previous account's operations.

Known conflict behavior: if different devices reorder and edit the same
playlist while disconnected, the server rejects incompatible membership
rather than deleting or silently replacing a device's pending changes.
Those edits remain local until reconciled; automatic collaborative conflict
resolution is outside this transitional synchronization feature.
