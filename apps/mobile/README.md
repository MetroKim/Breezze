# Breezze

Breezze is a free, listener-first music app built with one Flutter/Dart application codebase. It has four primary destinations: Home, Browse, Library and Search. Downloads live inside Library. There is no artist portal, artist upload workflow, subscription, membership, billing or paywall.

## Current client capabilities

- Search track metadata through Breezze's backend-connected discovery adapter.
- Play tracks only after the Breezze backend resolves a canonical catalog track and authorizes playback for the account and territory.
- Persistent mini-player, Now Playing, queue controls, favorites and local listening history.
- Android/iOS OS media sessions use one global PlayerController. macOS, Windows SMTC and Linux MPRIS now attempt the same audio_service handler and fall back safely when unavailable; desktop media keys remain UNVERIFIED. Web Media Session integration remains incomplete. Do not call these platform features verified until each OS passes native tests.
- Android foreground media playback service declarations and iOS audio background mode are applied by `tool/generate_platform_targets.sh` when native runners are generated.
- Mobile audio focus is configured for music playback; calls/other exclusive interruptions pause playback without auto-resuming, and headphone/Bluetooth route removal pauses to prevent speaker leakage.
- Local playlists with account-scoped storage and optional backend synchronization.
- Offline downloads through backend authorization and signed media URLs.
- LRCLIB lyrics lookup with track-change-safe loading.
- Responsive layouts for compact phones through expanded desktop windows.
- Apple-inspired platform UX without proprietary assets: four stable tabs, adaptive glass transport, native iOS detail transitions and action sheets, Android/desktop platform parity, Dynamic Type and reduced-motion fallbacks.
- Mobile music-session setup precedes playback source preparation. Interruption and route-loss handlers pause without automatically restarting a song after a phone call.
- Original Breezze SVG interface icons, light/dark themes and reduced-motion-aware loading states.

Discovery metadata is not a playback license. The app never treats a YouTube Music metadata result as a directly playable or downloadable stream.

## Requirements

- Flutter stable (Dart 3.4 or newer).
- Breezze API running and reachable from the target device.
- A configured catalog/discovery sidecar and authorized playback provider for live music playback.

## One-command development launch

Run `bash run.sh` from the repository root or `bash tool/run_dev.sh` here.
The launcher generates missing Drift code, prepares web SQLite assets when
needed, then uses `web-server` for Codespaces/headless Linux and the native
Linux runner when a display is available. Codespaces browser preview uses port
8080 by default. The Linux desktop target is checked into this repository;
GTK development packages and a GUI session are still required.

## Generate native platform runners

From the repository root:

```bash
cd apps/mobile
bash tool/generate_platform_targets.sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

The runner bootstrap creates Android, iOS, Web, Linux, macOS and Windows platform folders around the shared `lib/` code, then adds the Android foreground media service/permissions and iOS `UIBackgroundModes=audio` declarations required for background playback. It does not install platform SDKs, configure signing, guarantee plugin support or replace native platform validation. One audio_service handler is attempted on Android/iOS/macOS/Windows/Linux, using installed audio_service_mpris and audio_service_win packages on supported desktops. Incompatible/missing OS media services safely use a no-op bridge. Web has no active media-session bridge here. Linux MPRIS seek and media-key behavior require actual desktop testing. Build and test each target on its supported host.

## Configure the API

The default API URL is `http://localhost:3000`. Override it at build/run time with a Dart define:

```bash
flutter run --dart-define=BREEZZE_API_URL=http://localhost:3000
```

For a physical phone, use the development machine's LAN address instead of `localhost`, and make sure the API is reachable over the local network. Production builds must use the deployed HTTPS API origin.

## Analyze and test

From `apps/mobile/`:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --reporter expanded
```

Example platform builds (after runner generation and platform prerequisites):

```bash
flutter build apk
flutter build web
flutter build linux
flutter build macos
flutter build windows
flutter build ios --no-codesign
```

Linux builds require the Flutter Linux desktop dependencies (including GTK development headers, CMake, Ninja and Clang). macOS and iOS builds require macOS with Xcode; Windows builds require Windows desktop build tools. Each target must be built and tested on its supported host.

## Apple-inspired experience

Breezze uses Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) for discoverability, content hierarchy, modality and accessibility **without** copying the Apple Music app or using private Apple media APIs. Details are routed through `app/breezze_navigation.dart` (native iOS back gestures, reduced-motion fallback), and Now Playing uses `widgets/bz_transport_controls.dart` for responsive transport controls. Only one `PlayerController` is allowed; `just_audio` plus `audio_session` interfaces with AVFoundation/ExoPlayer and `audio_service` mirrors state to the lock screen. See [architecture contract](../../docs/architecture/BREEZZE_APPLE_PLATFORM_EXPERIENCE.md).

## Architecture

```
apps/mobile/                 Flutter application and platform adapters
packages/design_system/      Breezze design tokens, glass surfaces, SVG UI
packages/audio_contracts/    Playback state, queue, lyrics and audio contracts
packages/api_client/         Typed Breezze API transport and client contracts
backend/api/                 Auth, catalog, rights, playback and library APIs
infra/cloudflare/            Edge API and media delivery workers
docs/design/                 Interface contract and responsive visual spec
docs/architecture/BREEZZE_APPLE_PLATFORM_EXPERIENCE.md
                             Apple-inspired UX / native media session architecture and QA gates
```

## Product and rights boundaries

- Breezze is an independent product and is not affiliated with other music services.
- Artist records are listener-facing catalog metadata only; there is no artist portal or artist account workflow.
- Search metadata does not grant playback or download rights.
- Playback and downloads are backend-authorized and territory-aware.
- Editorial charts, regional rankings, music videos, concerts, album credits and artist catalog pages require verified provider data. Empty states are intentional until those sources are connected.
- The app is free to use; no subscription or payment UI is part of the product.
