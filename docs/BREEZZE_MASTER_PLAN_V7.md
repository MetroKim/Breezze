# BREEZZE MASTER PLAN v7 — Unified Flutter, all operating systems and evidence-based completion

**Updated:** 26 November 2026. **Repository:** [MetroKim/Breezze](https://github.com/MetroKim/Breezze), authoritative branch `main`.
**Status:** IN DEVELOPMENT / RELEASE FROZEN. A commit, static code review, package builder, or old CI run does **not** mean the app is finished.
**Authority:** This document supersedes older status/priority checkmarks in v5, v6, the historic roadmap and old gap register. Existing approved architecture decisions in `docs/architecture/BREEZZE_V6_MAINLINE_INTEGRATION.md` remain in force unless explicitly amended below. Reconcile against current GitHub main and production services before changing anything destructive.

## 1. Non-negotiable product contract

Breezze (two z's) is an independent, free, listener-first Flutter music client, with an original B-note identity and an **Apple Music-inspired** content-first visual language. Spotify's design/accessibility docs inform quality only; Spotify metadata can be used only under relevant partner rules. Breezze must **not** become a Spotify or Apple Music visual clone.

- One shared Flutter application in `apps/mobile` serving **Android, iOS, Windows, macOS, Linux desktop and web**. Platform-specific runners/adapters are allowed; six divergent apps are not.
- Exactly four primary tabs: **Home / Browse / Library / Search**. No Radio fifth tab. Responsive sidebar on large displays; one persistent mini-player and full Now Playing.
- One authoritative `PlayerController`, queue, position clock, account ownership, playback error/rights state and history pipeline. No second engine inside video, album, search or downloads screens.
- Required sign-in before Home (Supabase Auth staged behind existing API); email verification, Google configured with real registered native clients; Apple button can stay visible but disabled until activation. No fake authentication.
- User-owned saved music metadata, followed artists, pinned items, multi-playlist actions, replay, search and listening preferences; offline data belongs to the signed-in account.
- Never promise full-track playback from metadata. **Spotify primary artist/catalog sections; Deezer verified fallback for gaps subject to production partner approval; Deezer native previews are short clips only; ytmusicapi is discovery/metadata only; official YouTube video is via the authorized in-app official player.** No ARL cookie bypass, unofficial streaming extraction, unlicensed caches or downloads.
- Native full-song audio and offline downloads can ship only for **app-owned or appropriately licensed** recordings and territories through backend-approved grants, isolated media delivery and explicit offline rights.
- No advertising, subscriptions, billing or source-code releases. Existing release freeze is binding until owner approval after all gates pass.

## 2. Authoritative technical architecture (do not duplicate)

| Layer | Single authority / integration |
| --- | --- |
| Flutter UI / state | `apps/mobile`, Riverpod, Breezze design-system package; Apple HIG-inspired interactions; platform-adaptive navigation, accessibility, dark/light |
| Player | `features/player/player_controller.dart`; `packages/audio_contracts` queue and states |
| Audio rendering | `just_audio`: iOS AVFoundation, Android ExoPlayer, Linux/Windows via registered media_kit adapter; `audio_session` where supported; local/rights-cleared media only |
| OS media sessions | `audio_service` bridge for Android/iOS; desktop bridges need **real implementation and tests** (current startup returns no-op for web, macOS, Linux, Windows) |
| Local/offline | Drift/SQLite, encrypted account-scoped storage, secure session keys and outbox; rights leases / revocation revalidation |
| Identity | Supabase Auth with legacy identity mapping and backend-issued authorization; never remove legacy data without migration |
| Primary API | NestJS/Prisma `backend/api`, account/territory checks, playback authorization, library sync |
| Data | **Verify real deployed topology:** Railway Postgres currently documented as API operational DB, Supabase as identity/profile layer. Do not silently assume all Prisma tables were moved to Supabase |
| Catalog/discovery | Spotify-primary artist pages, tightly identity-matched Deezer optional supplement, YouTube Music metadata, LRCLIB/JamBase only for specifically supported licensed/attributed capabilities |
| Edge and media | Cloudflare API Worker, private R2-backed media Worker for owned/licensed assets, short-lived signed grants / byte-range delivery; no generic third-party rehosting |
| Developer contracts | OpenAPI client package, Prisma schema migration history, typechecked workers, CI and stage-specific observability |

## 3. Platform qualification matrix

**A Flutter build on one OS does not certify execution, system integration, install packaging or feature parity on another.** Target versions/CPU architectures must track official Flutter supported platforms and plugin compatibility; do not hardcode assumed timeless OS support.

| Target | Build baseline | Required functional acceptance | Distribution gate |
| --- | --- | --- | --- |
| Android phone/tablet | Flutter APK debug/release and eventually appbundle on Linux CI | Emulator plus physical phone, playback focus/calls/noisy route, notification/lock screen/media buttons, Google login, downloads | Signed store package + Play policies; **not released** |
| iPhone/iPad | Flutter iOS `--no-codesign` on macOS, simulator | Native route, interruptions, lock screen, VoiceOver, Dynamic Type, background audio, Apple/Google login as provisioned | Xcode signing, provisioning, App Store review; **not released** |
| Windows desktop | Flutter Windows on Windows host | window resize, keyboard, local files, background audio, taskbar, media keys / SMTC, secure storage | Signed installer/MSIX after acceptance; **not released** |
| macOS desktop | Flutter macOS on macOS host | resize, keyboard, file picker, macOS Now Playing/media keys, sandbox and notarization, secure keychain | Codesign/notarize/package; **not released** |
| Linux desktop | Flutter native ELF bundle on supported Linux/glibc systems | GTK launch on X11/Wayland, portal file dialogs, secrets/keyring, local audio, MPRIS/media keys, audio backend, DPI/theme, multiple distros | Baseline x86_64, ARM64 separately if toolchain supports; tarball, AppImage, Flatpak, Snap, .deb, .rpm **qualification only, no distribution** |
| Web/PWA | Flutter release web | browser playback restrictions, storage, responsive UX, auth and official embedded YouTube, keyboard and screen readers | Secure HTTPS hosting, browser matrix, service worker privacy; **not released** |

### Linux is a compatibility matrix, not an impossible "one build on every distro" promise

**First native Linux qualification:** x86_64 glibc desktop, including clean **Ubuntu 22.04 and 24.04, Debian 12, current Fedora and current Arch** runtime-linkage checks. Add Rocky/Alma/RHEL, openSUSE, Linux Mint and Pop!_OS as separately evidenced runtime tests; none are implicitly certified by family resemblance.

- Standard Flutter Linux shell needs GTK 3 / compatible glibc, bundled Flutter engine and needed shared libraries, display server, GPU drivers, audio backend, user-session services and plugin support. **Authenticated native desktop sessions also require an available and unlocked Secret Service-compatible keyring (GNOME Keyring or KWallet) for secure credentials.** Never fall back to plaintext token storage on distributions without a keyring.
- `apps/mobile/tool/linux_portability_audit.py` checks release ELF architecture (including versioned `.so` files), essential bundle files, native libraries, escaping symlinks, and accidental source/secrets inclusion. `.github/workflows/breezze-linux-distro-compat.yml` builds on an older glibc host and checks linking in Ubuntu, Debian, Fedora and Arch containers. **Linker success is NOT GUI/playback success.**
- For graphical smoke tests, test X11 and Wayland (GNOME/KDE), desktop portals, headless behavior, both light/dark, scale 100–200%, keyboard and screen readers. For audio, test PipeWire and PulseAudio plus Bluetooth route changes. Check disk file picker, downloads, secure storage and single-instance behaviors.
- Document/test packaging separately: portable compressed bundle, .deb (dpkg), .rpm (dnf), AppImage, Flatpak/Flathub and Snap. Sandboxed paths/portals/MPRIS permissions and codecs may differ by format. **No release installer or upload before freeze is lifted.**
- ARM64/AArch64 Linux requires a separate supported build runner and native plugin/ELF verification. Linux Alpine/musl is **not** natively supported by a glibc-targeted Flutter bundle without a separately validated runtime; web is a fallback where available. Do not claim "all Linux distributions" PASS from only Ubuntu or from Docker `ldd`.

Official references: https://docs.flutter.dev/reference/supported-platforms , https://docs.flutter.dev/platform-integration/linux/building , https://docs.flutter.dev/deployment/linux .

## 4. Evidence register — exact revision, no inherited green checkmarks

**Observed baseline before v7 edits:** `578d8e42b8b9c690d06b5eff6411096fd9fb94d4` on main. On 26 Nov, all nine jobs for [CI run 45792568500](https://github.com/MetroKim/Breezze/actions/runs/45792568500) were **queued**; [Android 45792568545](https://github.com/MetroKim/Breezze/actions/runs/45792568545) and [iOS 45792568664](https://github.com/MetroKim/Breezze/actions/runs/45792568664) were **pending**. These are not green. Newer commits must be checked using their own SHA/run IDs, not these historic statuses.

| Evidence gate | Current verified status / criteria for PASS |
| --- | --- |
| Source identity & release security | Repo `MetroKim/Breezze` observed **public**, `main`, with **zero current published GitHub Releases**. Public repository content remains clonable despite no release. No build/release artifacts may be published until owner approves |
| Flutter mobile analyzer/unit tests | **PENDING** latest-head `flutter analyze` and `flutter test`, generate Drift first; do not reuse older green CI |
| API Client / design system / audio contracts | **PENDING** dependency, analyzer and unit suite on exact main SHA |
| NestJS/Prisma | **PENDING** generate, validate schema, apply migrations to disposable test PG, typecheck, Jest, build |
| Cloudflare Workers | **PENDING** typecheck, signed media and byte-range tests on exact SHA; staging != production |
| Windows / Linux / Android / web builds | **PENDING** per-host CI build jobs; no release verification implied |
| macOS and iOS builds | **PENDING** macOS runner build/Flutter target generation |
| Linux cross-distro ELF gate | **PENDING** new multi-image compatibility workflow; cannot infer GUI/audio parity |
| Linux portability auditor — Python unit tests | **PASS 7/7, independently executed 26 Nov 2026:** Python 3.13.5 compiled and ran tests after verifying local copies matched Git blob hashes `c1f6ffd3e19c3a559d8c3344b3186026caef5de9` (audit) and `ddac69b80847c74ff03cf73ab98bc41d84e8b410` (tests). This proves only audit logic and security rejection cases, **not a Linux release build** |
| Desktop media-session disconnection and late-disposal tests | **IMPLEMENTED, UNVERIFIED:** `background_audio_sync_test.dart` now checks OS projection fallback and late failures, plus actual status is shown under Settings > Playback. Requires Flutter CI and native OS tests |
| Android/iOS emulators | **PENDING** exact-head integration runs, explicit test paths and log artifacts |
| Real devices and OS services | **NOT VERIFIED** VoiceOver/TalkBack, Bluetooth physical routes, AirPlay/MPRIS/SMTC, mobile interruptions, native store sign-ins |
| Full-track streaming/offline catalog | **BLOCKED BY RIGHTS/REAL ASSETS** until approved recordings, grants, revocation and end-to-end delivery are verified |
| Production deployment + DB reconciliation | **UNVERIFIED ON CURRENT HEAD**; must compare Railway, Supabase, Cloudflare and DB migrations without changing prod blindly |
| Security and launch | **FROZEN** until owner approves after every P0/P1 evidence gate |

**Confirmed compile failures and corresponding patches (not yet green):** GitHub Actions Linux build job [139825696015](https://github.com/MetroKim/Breezze/actions/runs/45795711556) identified the `AudioService.init` type inference error, invalid integer `||` Search comparator, and nullable concert-country expressions. GitHub CI [45778780431](https://github.com/MetroKim/Breezze/actions/runs/45778780431) independently reported Search analysis and a one-test Spotify artist release-date mismatch. Corrective commit [`8e4cbbd`](https://github.com/MetroKim/Breezze/commit/8e4cbbd293bf7227d81fb4f51d3295898e49ff04) fixes these code paths and pins the release-date test clock. Subsequent commit [`7d5dda9b`](https://github.com/MetroKim/Breezze/commit/7d5dda9b14cd2ed99f7f242beb3e9c146895f20c) fixes a separate P0 `just_audio.play()` lifecycle hang by not awaiting a Future that completes at song end/pause. **These fixes are source-implemented only until the exact new source revision has a passing CI + native emulator result.**

**Local test evidence (narrow and reproducible):** `python3 -m py_compile linux_portability_audit.py test_linux_portability_audit.py` succeeded, and `python3 -m unittest discover -s <audit-directory> -p 'test_linux_portability_audit.py' -v` reported **7 tests in 0.015s, OK**. Each copied file's Git-object SHA-1 was checked against the GitHub API result before testing. Do not represent this as a Flutter compile, emulation, distro GUI or user playback PASS.

**Status vocabulary:** `IMPLEMENTED` = source present; `PASS` = supported automated/device evidence on matching SHA; `FAIL` = reproducible failed assertion; `QUEUED` = job hasn't run; `BLOCKED` = external dependency/rights/credentials; `UNVERIFIED` = missing evidence. Never convert `QUEUED` to `PASS`.

### 26 Nov read-only production topology check (not a deploy or E2E test)

- **Railway:** Breezze production environment currently reports four live services: Breezze API, Postgres, Breezze Catalog Metadata, and Redis, each with a SUCCESS latest deployment state. The API has **live-with-staged-changes**, and the environment has **two pending staged changes**. Do not accept/deploy until release freeze, full CI and DB migration backups are cleared. A successful infrastructure deployment is not proof of full playback.
- **Supabase (verified and privilege-hardened):** Project ACTIVE_HEALTHY, three existing public tables (`profiles`, `user_library`, `pinned_playlists`) with RLS enabled. Discovered that `authenticated` had `TRUNCATE`, `REFERENCES`, `TRIGGER` and `MAINTAIN` privileges beyond CRUD (TRUNCATE bypasses RLS). Applied *recorded production migration `20261126100716_breezze_revoke_rls_bypass_grants`* to revoke those four privileges from `anon` and `authenticated`, **without changing records or RLS ownership policies**. Post-migration `has_table_privilege` queries returned false for all four high-risk privileges and true for SELECT/INSERT/UPDATE/DELETE for authenticated on all three tables; RLS remains enabled; security advisor still returns zero lints. These are narrow SQL security checks, not tested user sign-in or cross-tenant attack simulations. Full record in [security audit](security/BREEZZE_SUPABASE_RLS_SECURITY_VERIFICATION_20261126.md).
- **Cloudflare (live configuration read-only):** Worker scripts `breezze-api-edge`, `breezze-media`, `breezze-media-qa` and R2 buckets `breezze-media`, `breezze-media-qa` are present. API Worker has `API_ORIGIN` (plain-text) and `EDGE_SHARED_SECRET` (secret-text) binding; both media Workers have `MEDIA_BUCKET` (R2) and `MEDIA_SIGNING_KEY` (secret-text). **Binding presence is not proof of valid signing, asset rights or a passing live data path.** No Worker was deployed or secret value revealed.
- **Railway deployment drift:** Latest observed successful production Breezze API deployment points to commit `13b6c9e7407bfa576a02b94b2b569f8f79cc5b03` (25 November), **not** the current v7 mainline. Do not blindly promote new commits while release freeze / build failures remain. Current API tests cover a source state newer than production.
- **GitHub:** repository remains public with zero published Releases. Public source remains accessible to anyone with the URL; owner approval is necessary for visibility changes. All latest-SHA Actions still need verified conclusions.

### 26 November — P0 remediation implementation and remaining evidence

- **Linux hard compile failure:** Linux [run 45798705250](https://github.com/MetroKim/Breezze/actions/runs/45798705250) failed due to Clang rejecting the GCC-only `-Wno-error=deprecated-literal-operator`. In commit [`7afd616b`](https://github.com/MetroKim/Breezze/commit/7afd616bd7c9f8755a16b4139ffe77c6d12d6a29), CMake now selects this flag only for appropriate GNU compilers, removing the workflow's unsafe sed patch. **Source fixed, rerun not yet verified PASS.**
- **OS audio interruptions:** In `just_audio_engine_adapter.dart`, route/focus interruption is now signalled before native pause; the app still never auto-resumes without a user action. Physical-call/headphone tests remain mandatory.
- **Accessibility:** Flutter guideline checks added for Android/iOS tap targets and semantic labels on transport controls; physical VoiceOver/TalkBack verification remains open. [Physical QA protocol](qa/PHYSICAL_DEVICE_AND_ACCESSIBILITY_ACCEPTANCE.md).
- **Linux D-Bus:** `apps/mobile/tool/check_linux_mpris_session.sh` now probes the actual exported MPRIS Player interface; CI attempts this inside an isolated X11/D-Bus session. A detected interface is not full media-key validation. Tests may still fail until underlying plugin initialization works.
- **Rights-cleared complete recordings:** The isolated `media-live-qa.yml` workflow now targets 125-second original AAC, R2 full byte integrity and far ranges. This verifies a permissible infrastructure test, not any commercial music license. [Authorized media roadmap](architecture/BREEZZE_AUTHORIZED_FULL_TRACK_PATH.md).
- **External blockers:** physical test devices/headsets, verified OAuth registrations, owner-controlled signing certificates, independent label/master/composition licenses, and passing build/emulator CI remain explicit dependencies. No status is silently promoted from source present to PASS.

## 5. Ordered engineering execution (one owner, one backlog)

### P0-A — Stable CI and regression gate [OPEN]

- Reconcile `main`, CI head SHA and queued GitHub Actions. Preserve error logs by job and run; fix the **first actual error** rather than retrying blindly.
- All platforms compile: Linux release/debug, Android debug/release, web release, Windows debug, macOS debug, iOS `--no-codesign`.
- Mandatory Flutter tests: navigation, scalable transport, player controller (queue/seek/end/interruptions), account switches, downloads, cross-device library, artist page/catalog source separation, authentication, accessibility and official YouTube embed.
- API tests: provider scopes, media grants and expiry, Cloudflare signed range requests, Prisma migration in ephemeral PG, Supabase JWT, regressions against cross-account leakage.
- Fail on real test errors. CI resources/runner scheduling are not equal to a product defect; record infrastructure delay separately.

### P0-B — OS playback correctness [OPEN]

- One PlayerController everywhere; no source spoofing, no native streaming from ytmusicapi, no audio engine duplication or unlicensed content in queue.
- Android: audio focus granted/denied, call/notification interruption, headphones/Bluetooth disconnect, foreground service and notification actions; resume **only** after explicit user action.
- iOS: AVAudioSession configured before source, background audio declaration, call/Siri interruptions, route changes, native lock-screen media actions; recheck that no automatic post-call resume occurs.
- **Desktop OS media integration advanced (UNVERIFIED):** `startBackgroundAudio` now attempts the same audio_service handler on Android/iOS/macOS/Windows/Linux and falls back to NoopBackgroundBridge when the native media service cannot initialize. macOS Now Playing, Windows SMTC and Linux MPRIS remain unverified for real hardware media keys, state and seek; web still has a no-op bridge. Require host-specific tests before marking PASS.
- Simulated events in unit tests are necessary but do **not** replace real device/Bluetooth validation. Physical-device results are explicitly still open.

### P0-C — Playback rights, reliable media and downloads [BLOCKED / PARTLY IMPLEMENTED]

- Supply a documented authorized full-length test asset and rights record; verify true complete playback, seek near end, pause/resume, background and interruption across devices.
- Test CDN byte ranges, asset ownership and territory, signed URL expiry, recovery without loops, 401/403 denies and provider failure. Private R2 assets only; no unauthorized YouTube/Deezer/Spotify rip/rehost.
- Offline downloadable right must be distinct from streaming, with per-account encrypted file storage, bounded licence expiry/revalidation and takedown behavior.
- Separate capability flags for preview/official video/full stream/offline; no promise of unlimited full song streaming before rights approval.

### P0-D — Secure identity, production data and source protection [OPEN]

- Required sign-in gate, email verification, Google native app ID + Android SHA/iOS URL scheme proof; Apple login activated only with Apple Developer capabilities/credentials.
- Supabase Auth sessions and Railway API user model must be reconciled without destructive Prisma history resets; QA migrations on disposable PG first, then backups/approved production cutover.
- Verify Cloudflare Workers and R2 secret bindings, deploy staged revisions first; production release freeze remains.
- GitHub repository public exposure must be explicitly reviewed by owner; zero published Releases does **not** keep source confidential.

### P1-A — Apple-quality Breezze experience and a11y [PARTIALLY IMPLEMENTED]

- Preserve Breezze glass/tokens/icon pack, iOS native detail routes and modal sheets, four tabs, single mini-player and semantic headings. No copied Apple Music private assets/UI.
- Validate iPhone and Android 320dp/200% scale, iPad/tablet, ultrawide desktop, desktop keyboard/mouse/gamepad where applicable, high contrast/reduced transparency/motion and screen reader control order.
- VoiceOver and TalkBack sign-in/search/library/player/queue/downloads with exact VoiceOver/TalkBack evidence; keyboard focus, MPRIS media keys, accessible non-drag queue alternative.
- Responsive UI snapshots across platforms; no overflow or unavailable actions masquerading as playable.

### P1-B — Listener feature completeness [OPEN]

- Home/Browse recommendations based on history/follow/skip signals with consent and stable data contracts; never fake personalization.
- Spotify-primary artists, accurate song credits, releases and album routing; Deezer fallback with exact artist match and explicit attribution when permitted. Full pages/search should not claim artist tours solely from Spotify metadata; JamBase concert country feeds need reliable filtering.
- Library account sync, pinned albums/artists, multi-playlist add, full-library batch actions; downloads, Replay/year-end reporting, LRCLIB and translated lyrics with meaningful availability status.
- Background/locking playback parity, responsive queue reorder and a keyboard-accessible queue alternative.

### P1-C — Linux distribution & desktop parity [OPEN]

- Commit Linux x64 compatibility tests and run them, then true startup/GUI/media-key tests on Ubuntu, Debian, Fedora, Arch plus RHEL/openSUSE derivatives and Wayland/X11 hosts.
- Fix plugin compatibility, glibc and libsecret/keyring/DBus/media_kit issues evidenced by tests; no unverified distro claims.
- Test Mac secure storage/media controls, Windows SMTC/file pickers, browser file/storage restrictions, and consistent sign-in/playlist/player behavior.

### P2 — Production hardening after P0/P1 [PLANNED]

- Release observability with privacy-safe error categorization, worker/DB metrics and rollback; no embedded production secrets in logs.
- Load tests for account libraries/search queue, cache invalidation, rate limits and DB transaction stability; deterministic builds and SBOM/licence audit.
- Native device lab, store privacy and entitlement approvals, signing/notarization, reviewed distribution packaging, threat model and owner go/no-go.
- Full end-to-end staging then production rollout only after explicit authorization.

## 6. How to verify exact-source acceptance

Run from `apps/mobile` after `bash tool/generate_platform_targets.sh` (on a supported build host), `flutter pub get`, and `dart run build_runner build --delete-conflicting-outputs`: `flutter analyze`, then `flutter test --reporter expanded`.

Run from `packages/design_system`, `packages/api_client`, `packages/audio_contracts`: `flutter pub get`; `flutter analyze --fatal-infos`; `flutter test --reporter expanded`. Run NestJS/Prisma via `.github/workflows/breezze-quality.yml` against disposable Postgres; run Worker tests and independent video/audio policy QA. Run mobile simulator integration tests with real Android and iOS hosts; review each log, SHA, status and screenshots/reports. Run the Linux portability workflow and separately verify GUI/audio in actual distro sessions.

**No silent skips:** each gate logs test name, platform, commit SHA, job URL, pass/fail/blocked, error cause, remediation and a re-test link. If one mandatory P0 gate fails or stays queued/unverified, the whole product stays **NOT RELEASE-READY**.

## 7. Release criteria and controls

Breezze becomes release-ready only when every required P0/P1 gate passes on the candidate SHA; Apple/Google login is honestly configured; owned/licensed audio and offline rights are verified in every intended territory; all declared OS/platform targets have certified functional builds or are explicitly scoped out; security/privacy review and code/source exposure controls are approved; and **the owner explicitly lifts the no-release freeze**.

Do not create GitHub Releases, bundle repository history, publish source archives, submit a store app, upload installers, or promote production media Workers while this freeze applies. CI-only compatibility checks do **not** grant release permission.

**Useful references:** [v6 decisions](architecture/BREEZZE_V6_MAINLINE_INTEGRATION.md) · [Apple platform experience](architecture/BREEZZE_APPLE_PLATFORM_EXPERIENCE.md) · [media rights gates](architecture/MEDIA_DELIVERY_RELEASE_GATES.md) · [source security freeze](security/BREEZZE_RELEASE_FREEZE_20261125.md) · [Linux compatibility workflow](../.github/workflows/breezze-linux-distro-compat.yml).
