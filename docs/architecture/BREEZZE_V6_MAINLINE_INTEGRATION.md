# Breezze v6 — Mainline Integration Contract

**Status:** Incremental adoption, not a claim of production readiness.  
**Target:** `MetroKim/Breezze`, default branch `main`.  
**Supersedes:** v5/v6 pasted structural proposals where they conflict with working code.  
**Product contract:** Free, no subscriptions/ads, four primary tabs: Home, Browse, Library, Search. One global player and mini-player.

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
