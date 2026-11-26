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
| **1. UX navigation** | Home / New / Library / Search; profile/settings; mini-player; no wrong labels | Flutter widget tests + accessibility labels, iOS and Android smoke | In progress |
| **2. Unified engine** | Single controller, rights-gated resolver, queue, signed sources, native focus | Dart unit tests; Android/iOS real decoder; no metadata-only full audio | In progress — existing foundation |
| **3. Media authorization & infrastructure** | Territory, rights, verified R2 variant, bounded signed URL, session lifecycle | Postgres/R2 integration, 200/206 bytes, deny expired/missing grants | Backend contract tests previously passed; full licensed catalog **blocked** |
| **4. Online AutoMix** | Pair analysis, dual-stream mix DSP or native verified transition, fallback and toggle | Two real authorized full tracks, seamless audible transition verified | Planning only; not complete |
| **5. Offline & error handling** | Queue/retry, offline leases, encryption, interruption/restart, explicit failure reason | Offline airplane-mode verified, account isolation, expiry/denial | Partial |
| **6. Native OS + accessibility** | Auto-resume calls, no Bluetooth leak, media buttons, VoiceOver/TalkBack, Linux MPRIS | Emulator + physical device acceptance scripts and actual logs | Pending |
| **7. Security, packaging & release** | Ignore credentials, secrets audit/rotation, signed Android/iOS/macOS/Windows/Linux artifacts, current-head CI | CI and CodeQL green, signatures verified, rights evidence, release checklist approved | BLOCKED |

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
