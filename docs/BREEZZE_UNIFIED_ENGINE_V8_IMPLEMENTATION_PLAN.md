# Breezze Unified Engine V8 — Implementation & Acceptance Plan

**Owner:** Breezze engineering | **Branch:** `main` | **Baseline:** `cb71606a124d94281a75402651455964d3a96f92` | **Started:** 2026-11-26 | **Release state:** BLOCKED until verified.

## Product contract (single source of truth)
- **Four top-level tabs in order:** **Home**, **New** (formerly Browse), **Library**, **Search**; no fifth Radio/Downloads/Settings tab.
- **Home:** listener-scoped history, favorites, follows, personalized shelves with honest source metadata. Do not label algorithmic shelves or charts as official without a real dataset.
- **New:** verified new releases, charts if licensed/attributed data exists, genre and mood discovery, music-video entry points.
- **Library:** saved songs, playlists, albums, followed artists, offline media, and download progress/failure recovery.
- **Search:** songs, artists, lyrics, and genre hubs; keep unplayable catalog results distinguishable from playable recordings.
- **Premium listening UX:** one mini-player, one Now Playing, consistent artwork, animations respecting Reduce Motion, Dynamic Type/text scaling, VoiceOver/TalkBack labels, keyboard/desktop navigation, and a stable back stack.
- **AutoMix:** online *optional* beat-matched transitions for **two authorized, simultaneously playable** audio streams; no provider extraction. A planning-only algorithm is **not** a mixed-audio engine. Fall back to gapless/normal transition if analysis, rights, decoder, or CPU budget is unavailable.
- **Offline:** rights-granted full tracks only. Encrypted, per-user app-private media with lease expiry/revocation, network/Wi-Fi gating, pause/resume/cancel, durable jobs, hash/integrity evidence, user-visible reason and retry; no YouTube/Spotify/Deezer metadata downloads.
- **Calls:** automatically pause during phone/exclusive audio interruptions, *resume after focus returns only if that same interruption paused active playback*, no intervening user pause/stop/track change, and current grant still authorized; **never** auto-resume after unplug/Bluetooth route removal.
- **Credentials:** client only receives public Supabase publishable key; server credentials remain in deployment secret stores or encrypted Supabase Vault with restricted SQL access. Add to `.gitignore`, never copy secrets into Git/issue/CI artifacts/logs or plaintext `public` tables. Inventory names and references, not values. Any exposed key must be revoked/rotated.

## Architecture (keep existing working services)
```
Flutter BreezzeShell (Home/New/Library/Search)
  -> global PlayerController + queue + OS audio_service
  -> PlaybackResolver / session + heartbeat (NestJS API on Railway)
  -> rights decisions (Prisma + Supabase Postgres)
  -> signed media worker (Cloudflare Workers + private R2)
  -> just_audio / ExoPlayer / AVFoundation / media_kit
```
Spotify/Deezer/MusicBrainz = discovery/metadata/previews only where licensed. YouTube Music = officially supported visible video playback. Only verified licensed Breezze assets or an actual authorized partner playback API can supply full-track native bytes. Secrets must **never** flow into the Flutter binary.

## Seven delivery stages (do not mark pass without evidence)

| Stage | Deliverables | Acceptance gate | Status |
|---|---|---|---|
| **1. UX navigation** | Home / New / Library / Search; profile/settings; mini-player; no wrong labels | Flutter widget tests + accessibility labels, iOS and Android smoke | Four shell labels wired; unit test added — CI/native pending |
| **2. Unified engine** | Single controller, rights-gated resolver, queue, signed sources, native focus | Dart unit tests; Android/iOS real decoder; no metadata-only full audio | Call auto-resume wired through player; policy + controller tests added; OS acceptance pending |
| **3. Media authorization & infrastructure** | Territory, rights, verified R2 variant, bounded signed URL, session lifecycle | Postgres/R2 integration, 200/206 bytes, deny expired/missing grants | Backend contract tests previously passed; full licensed catalog **blocked** |
| **4. Online AutoMix** | Pair analysis, dual-stream mix DSP or native verified transition, fallback and toggle | Two real authorized full tracks, seamless audible transition verified | Planning only; not complete |
| **5. Offline & error handling** | Queue/retry, offline leases, encryption, interruption/restart, explicit failure reason | Offline airplane-mode verified, account isolation, expiry/denial | Early rights denial, UI errors, per-asset-version HTTP range guard, backend SHA-256 identity, client SHA-256 integrity check and regression tests committed; **audio files still plaintext in app-private storage**, encryption/DRM and native acceptance pending |
| **6. Native OS + accessibility** | Auto-resume calls, no Bluetooth leak, media buttons, VoiceOver/TalkBack, Linux MPRIS | Emulator + physical device acceptance scripts and actual logs | Call-backend pause/resume race guarded and regression test committed; live `playerctl` transport acceptance script added; actual devices, TalkBack/VoiceOver and desktop keys pending |
| **7. Security, packaging & release** | Ignore credentials, secrets audit/rotation, signed Android/iOS/macOS/Windows/Linux artifacts, current-head CI | CI and CodeQL green, signatures verified, rights evidence, release checklist approved | .gitignore hardened and full-history Gitleaks v3 workflow committed (runner pending); Supabase Vault verified empty; credentials not migrated; signed builds/CI BLOCKED |

## Implementation rules
1. Make one scoped change at a time, with a regression test or exact manual acceptance command.
2. Update this plan and [master issue #27](https://github.com/MetroKim/Breezze/issues/27) with commit hashes and observed CI evidence; never claim PASS because a workflow is queued or code compiled only in theory.
3. Prioritize P0: compile, playback rights, login, media-session safety, secure keys, distribution; then P1: polish, AutoMix and personalizations.
4. Keep all platforms on the same authoritative player. UI cannot bypass backend rights.
5. GitHub release artifacts and source bundles stay unpublished until signed release approval.
6. If a test requires hardware, account credentials, license agreements or signing certificates, explicitly mark **External dependency** and include the exact acceptance checklist; do not fabricate evidence.

## Concrete acceptance matrix
- **Build/CI:** `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, Linux/Web/Android/iOS/Windows packaging jobs and CodeQL on the **same head SHA**.
- **Android/iOS:** signed-in playback with licensed 180+ second file; queue/seek/pause, lock-screen transport, incoming call pause/resume, manual pause during call must not auto-resume, headset/Bluetooth unplug must not auto-resume, OS interruption on/off, force-close recovery.
- **Accessibility:** real VoiceOver/TalkBack focus order, descriptive labels, 200% text, contrast, Reduce Motion and keyboard traversal.
- **Linux:** desktop launch under supported distro, MPRIS D-Bus registration **and transport commands** plus hardware media-key smoke.
- **Offline:** verified media bytes, correct user account isolation, AES authenticated encryption, restarts, Wi-Fi-only, integrity tamper rejection, grant expiry and revocation.
- **Signing:** Android AAB/APK production keystore fingerprints; iOS archive/provisioning; notarization for macOS; Authenticode/MSIX as appropriate on Windows; Linux package signing.
- **Catalog rights:** proof per recording, territory, duration and offline permissions; measured byte delivery; no rights inferred from metadata or R2 object names.

## Credential migration SOP (no secret values in commits)
1. Inventory **names** from Railway/Cloudflare/Google/Supabase and tracked config. Treat historical leaked values as compromised and rotate at origin.
2. Put active runtime secrets in the provider's encrypted environment/secret manager; optionally mirror necessary database-used secrets into Supabase **Vault** (encrypted at rest), with least privilege and a strictly server-side lookup.
3. Keep database catalog of `name, owner_service, vault_secret_id, rotation_at` only; never place decrypted secret values in exposed tables or call Vault from Flutter.
4. Gitignore `.env*`, platform signing files, local config and credentials. Keep sanitized `.env.example` templates, not real values.
5. Acceptance: automated secret scan + manual rotation confirmations, 401/403 fail-closed tests, no key in generated client assets.

## Status at plan creation
- **Known passing:** previous media delivery backend contract workflow [45779621949](https://github.com/MetroKim/Breezze/actions/runs/45779621949), on an older commit.
- **Pending current SHA:** [main CI 45802553236](https://github.com/MetroKim/Breezze/actions/runs/45802553236), [CodeQL 45802553174](https://github.com/MetroKim/Breezze/actions/runs/45802553174); Android/iOS simulator workflows had no pass at creation.
- **Critical blockers:** no verified paid/licensed full-song catalog nor rights to general Spotify/YouTube tracks, no signed distribution credentials/evidence, unverified physical device and VoiceOver/TalkBack acceptance.
- **Privacy note:** repository was public when implementation started; no secrets or production binaries may be committed.

## Follow-on checkpoint — recording identity, interruption sequencing and credential audit

- **Backend asset identity**: `backend/api/src/downloads/downloads.service.ts` now exposes `assetVersion` only when the verified `AAC_256` asset has an actual 64-hex SHA-256, rather than relying on an arbitrary metadata ID. Test: `backend/api/src/downloads/downloads.service.spec.ts`. Commits `a9d3d5e`, `51a715e`.
- **Exact resumption identity**: `packages/api_client/lib/src/downloads_library.dart` binds each resumable fragment to the owner, canonical track, and asset version; unversioned/mismatched fragments restart from byte zero. Parses complete HTTP `Content-Range` rather than a weak prefix; rejects wrong offsets. Computes the final SHA-256 for authenticated digest-bearing assets before writing successful metadata. The app forwards `AuthorizedDownloadGrant.assetVersion` to the client. Tests include valid/mismatched hash, stale fragments, and malformed HTTP 206. Commits `264ac9f`, `42bc29a`, `64002a0`, `5e9e3a6`, `fa77844`, `e2c333f`, `52f5bb2`.
- **Short-call race**: `PlayerController` now awaits the backend's in-flight pause acknowledgement before issuing call-restored resume. Tests cover a delayed pause RPC; this is NOT native telephony acceptance. Commits `6c979f9`, `6426d44`.
- **Linux media acceptance**: `apps/mobile/tool/check_linux_mpris_transport.sh` exercises real D-Bus Pause, Play and PlayPause transitions *with an authorized recording already playing*. Physical media keys, Seek and actual audio output remain unverified. Commit `38bac7e`.
- **Credential history**: `.github/workflows/v8-secret-history-guard.yml` uses Gitleaks v3 with full-history checkout and disables artifacts/comments/summaries. The scan has been **queued**, not proven passing. Every historical finding requires source-side rotation. Commit `b9a5317`.
- **CI status**: all current-run statuses must be observed on the final candidate `main` SHA. GitHub queued/cancelled workflows are **not** build/test passes. The repository remains release-blocked.
- **Outstanding critical requirements**: verified authorized catalog rights, encrypted offline-media-at-rest/approved DRM, executable two-stream online AutoMix rendering, native device/OS accessibility evidence, signed and verified installers, and a successful full current-SHA CI/CodeQL sweep.

## V8 execution ledger — 2026-11-26

| Area | Source evidence | Status |
|---|---|---|
| Four-tab navigation | `main_tab.dart`, `bz_shell.dart`, `breezze_navigation_test.dart`; commits `af75086` / `77762ba` / `c7c9554` | Code committed; Flutter test pending |
| Calls auto-resume | `call_auto_resume_policy.dart`, `JustAudioEngineAdapter`, `PlayerController`; tests `call_auto_resume_policy_test.dart` and `player_controller_test.dart`; through `4092a49` | Code committed; simulated unit tests pending; real telephony pending |
| Offline error handling | `DownloadsController`, `DownloadsScreen`; fail-closed policy and UI errors; commits `f850224`, `69728b2` | Code committed; app/airplane-mode/lease tests pending |
| Secrets | `.gitignore`, [custody record](security/BREEZZE_V8_SECRET_CUSTODY.md); Vault installed with **zero** entries; Gitleaks history scan has succeeded on multiple recent commits | Current source scanning works; real key rotation and selected Vault migration not completed |
| Licensed catalog | Previous backend contract suite passed on old SHA; no verified recording-level distribution/offline contract | **External licensing dependency / blocked** |
| Online AutoMix | `Automix.plan` plus `OnlineAutomixRenderer` equal-power two-deck overlap with authorization/decoder failure tests; actual native/global player connection and pitch-preserving BPM DSP are still missing | **Partially implemented; integration and native evidence blocked** |
| Offline encryption | BZA8 chunked AES-256-GCM audio encryption, per-user device key store and authenticated seek-source are now in mobile/API-client code; partial downloads may still create transient plaintext until sealed | **Implemented in source; native/security acceptance pending** |
| Signed packaging | Release/CI runners, signing keys, stores and hardware acceptance | **Not verified** |

**Next change order:** (A) current-commit Flutter CI; (B) OS/native interruption acceptance; (C) correct offline encryption/DRM and storage migration; (D) real licensed tracks and online dual-player DSP; (E) device accessibility + desktop MPRIS acceptance; (F) production signing and release freeze review. No green release status until all gates pass.


## Continuation checkpoint — 2026-11-26 (V8.1: CI reliability and account isolation)

**No release claim:** a GitHub Actions run is PASS only after completion against the exact release candidate SHA; pending, queued, running or cancelled is never a pass.

- **Navigation contract:** the identity guard now checks the canonical `Home / New / Library / Search` labels. Older guard failed on literal legacy `Browse` assertions; new source-based guard is committed and an earlier pipeline has shown identity guard SUCCESS.
- **Search regression:** `search_typeahead_test.dart` previously failed because its global `find.text('Songs')` found two headings across nested routes. The test now searches inside `SpotifyArtistScreen`. The Spotify/Deezer discovery + video isolation workflow `45812828461` returned SUCCESS on this change (`f11eccb`); full quality CI remains separate.
- **Private download jobs:** the previous shared `Downloads/jobs.json` contained one account's song titles/statuses after a different listener signed in. `DownloadJobOwnerDirectory` now derives a fixed owner-hashed private directory; `DownloadsController` clears pending status on auth changes, cancels prior-owner transfers, discards late transfer updates and serializes owner-scoped job writes. Legacy shared job file is removed instead of reassigned. Tests: `download_job_scope_test.dart`, `download_job_account_isolation_test.dart`. These are committed but **Flutter execution must still pass**.
- **CI scheduling:** `.github/workflows/ci.yml`, `breezze-quality.yml`, `codeql.yml`, and `v8-secret-history-guard.yml` use `cancel-in-progress: false`. This preserves the active build/scan while GitHub retains only the newest pending run on each ref. Do not equate an older successful SHA with validation of current main.
- **Security scan:** V8 secret-history guard `45813467262` completed SUCCESS on `7e53d6f`; it is not proof that historical leaked provider keys have been revoked or replaced.
- **Backend deployment drift:** Railway production's latest verified successful Breezze API deployment is commit `13b6c9e7` (2026-11-25), behind the current V8 main. Connected Supabase `djwvyjtebmsavhcrmhxf` lacks Prisma catalog tables `Track` and `AudioAssetVariant`. Preserve the current Railway `DATABASE_URL` until the authoritative DB and migration process are established; **never** direct production to an empty Supabase catalog.
- **Outstanding P0:** exact current-SHA Flutter/Windows/macOS/iOS/Android/Linux/Web CI and CodeQL; physical and simulator media-session/accessibility evidence; verified rights-cleared full-track catalog and offline grants; qualified online dual-source AutoMix; release-only signing certificates/keys and reproducible signed installers. Provider metadata alone cannot close rights gates.

See the same-sha evidence links and outstanding blockers in [master issue #27](https://github.com/MetroKim/Breezze/issues/27).

## V8.2 checkpoint — CI diagnostics and real two-deck renderer (2026-11-26)

**Latest source changes before this document:** `0596004b0f330d3596139d8470fff467039b74b1`.

- **Confirmed CI root causes:** older Linux build job `139886845648` stopped on Clang treating old `flutter_secure_storage_linux` nlohmann JSON literal operator warnings as errors; Linux compatibility job `139886915162` failed startup because `media_kit` could not locate `libmpv`. Another Linux build failed because older Clang 14 does not recognize `-Wno-error=deprecated-literal-operator`. Fixes: narrowly scope plugin-only diagnostic to **Clang 19+** (`apps/mobile/linux/CMakeLists.txt`) and install `libmpv-dev` for Linux build and compatibility test images.
- **Confirmed Flutter failure:** old Flutter test job `139886846026` failed four tests when `DownloadsController` wrote to `downloadJobStatusProvider` during Riverpod provider initialization. Fixed by removing that initialization-time cross-provider write, deferring account-switch notification until a microtask, and updating corresponding test timing.
- **Online AutoMix renderer added:** `packages/audio_contracts/lib/src/online_automix_renderer.dart` drives genuinely simultaneous independent decks through a bounded equal-power overlap; checks authorization at every step; stops both when rights/focus disappear; restores outgoing only if rights remain valid on decoder failure. Unit tests in `online_automix_renderer_test.dart`. **Still not wired to the active global PlayerController/just_audio dual-deck lifecycle**, and no native pitch-preserving tempo stretch. Never mark user-facing AutoMix PASS from the isolated unit tests.
- **Offline audio protection:** `BreezzeOfflineAudioCipher`, `secureDownloadsLibrary`, `BreezzeEncryptedOfflineAudioSource` now implement chunked authenticated AES-256-GCM media, device-held per-user keys, and seekable memory-only decryption. **Transient plaintext during initial download** and real-device decoder/keystore/call-interruption acceptance still need separate review; DRM/rights are distinct from AES.
- **Railway production:** all four services (Breezze API, catalog metadata, Redis, Postgres) reported online with no active failures. However API's last successful production deployment was **older** than V8. Railway has an **unapplied staged change** containing `YOUTUBE_DATA_API_KEY` and an API service config update; do **not** apply that patch automatically or conflate it with a verified V8 deployment.
- **Security:** Gitleaks history scan `45816216814` completed SUCCESS on `0596004b0`. This cannot revoke previously exposed provider keys and does not show a licensed media catalog.
- **Verification caveat:** CI `45816216878`, CodeQL `45816216664`, and Linux compatibility `45816216959` were **pending** when observed. The original build failures are fixed **in source**, not yet independently certified green on a final SHA. Do not publish signed/release artifacts.
- **External release dependencies:** a valid per-recording streaming/offline license manifest and actual recordings/territories; authorized Android/iOS/Windows/macOS signing identities and stores; physical-device telephone and Bluetooth tests; real TalkBack, VoiceOver and Linux hardware-key evidence. Neither generated synthetic QA audio nor Spotify/YouTube catalog metadata supplies commercial distribution rights.

**V8.2 acceptance priority:** green exact-head CI → native BZA8 decoder + interruption/accessible controls → connect and test authorized dual-deck AutoMix with two playback sessions → licensed catalog inventory and R2 delivery → signed installers + physical-device evidence → explicit release approval.


## V8.3 Linux portability candidate — Android JNI bridge isolation (2026-11-26)

**Observed main regression:** Linux compatibility [run 45816216959](https://github.com/MetroKim/Breezze/actions/runs/45816216959), job `139897392771`, successfully built the release bundle and passed an actual headless Linux app launch/MPRIS registration. Its cross-distro ELF linkage test then failed because the bundled `libdartjni.so` reported a missing `libjvm.so` dependency. This is **NOT** proof that all playback/media keys work.

**Candidate repair:** `apps/mobile/tool/linux_portability_audit.py` now supports explicitly removing that exact Android JNI bridge from the final Linux staging bundle **only after** `readelf` successfully verifies that neither the executable nor any other included native object has a direct `DT_NEEDED` dependency on `libdartjni.so`. If dependency inspection fails, the file is kept and the check fails. This does not ignore generic `ldd` errors, touch Android builds or remove arbitrary libraries. Four Python tests cover safe pruning, required JNI, failed inspection and no-op cases. The CI workflow retains its strict complete-bundle ELF/linker checks, actual process/MPRIS startup and four distro image linkage tests after pruning; PR trigger added.

**Acceptance:** the new exact-PR-head Linux portability workflow must pass; then verify a licensed actual track and media keys on Linux before claiming full native acceptance. A manually re-run earlier workflow or the previous MPRIS-only success does not certify this candidate.
