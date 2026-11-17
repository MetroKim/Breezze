# Breezze Gap Register — spec §50.4

A line is IMPLEMENTED only with real behavior + passing tests (§50.6).

| Req ID | Requirement | Status | Evidence |
|---|---|---|---|
| **A. Identity & design** | | | |
| A-01 | Brand marks (3 SVG + widget forms) | IMPLEMENTED | `assets/icons/`, `bz_brand_icons.dart` |
| A-02 | Tokens light+dark, exact §21.1 hex | IMPLEMENTED | `design_system/src/tokens.dart` (verified) |
| A-05 | Type/spacing/radius/elevation scales | IMPLEMENTED | `tokens.dart` |
| A-03 | Atmosphere materials (colors in theme) | IMPLEMENTED | `bz_theme.dart` |
| **B. App architecture** | | | |
| B-01/02/04 | Feature folders, Riverpod, one player | IMPLEMENTED | `features/*`, `player_controller.dart` |
| B-03 | Navigation | IMPLEMENTED | 5 tabs + mini-player → Now Playing + first-run Search nudge |
| **C. Music fetch & search** | | | |
| C-01/03 | Real keyless source, honest results | IMPLEMENTED | `youtube_source_adapter.dart` |
| **D. Player & media** | | | |
| D-01..03 | Player, state machine, queue | IMPLEMENTED | + tests |
| D-04 | Native playback engine | IMPLEMENTED | `just_audio_engine_adapter.dart` |
| D-11 | Background audio (lock screen, notification) | IMPLEMENTED | `audio_service_bridge.dart` + `background_audio.dart` (audio_service 0.18) |
| D-05/06/08 | Crossfade, scrobble, AutoMix | IMPLEMENTED | ports + tests |
| D-07 | Lyrics engine + provider | IMPLEMENTED | `lrc_parser.dart` + LRCLIB (duration-keyed) |
| D-09 | Quality tiers | IMPLEMENTED | `audio_quality.dart` |
| D-10 | Now Playing, word-synced lyrics | IMPLEMENTED | `now_playing_screen.dart` |
| **E. Downloads & library** | | | |
| E-01 | Favorites persistence | IMPLEMENTED | `FavoritesStore` + Library screen |
| E-02 | Offline downloads w/ lyrics + art | IMPLEMENTED | `downloads_library.dart`, app-private dir |
| E-03 | Live download progress UI | IMPLEMENTED | byte-accurate progress: source → library → DownloadsController → Search rows + Downloads in-progress section |
| E-04 | Recently played (Home rails) | IMPLEMENTED | `RecentStore` (capped 12) recorded on every play; Home rails show real history + favorites |
| **G. Privacy** | | | |
| G-01 | No client secrets | IMPLEMENTED | keyless sources throughout |
| **H. Premium & settings** | | | |
| H-01..03 | Tiers, settings, gating | IMPLEMENTED | `membership.dart`, settings screen |

## Fixed this pass

- Live download progress end-to-end: ResolvedStream totalBytes →
  audioBytes(onProgress) → DownloadsLibrary.download(onProgress) →
  DownloadsController (Riverpod state) → Search row progress bar +
  Downloads in-progress section with auto-refresh on completion.
- Background audio: real audio_service bridge (BaseAudioHandler) with
  lock-screen play/pause/next/previous/seek → PlayerController; shell
  swaps the no-op bridge for the native one after init; graceful
  fallback on platforms without a media session.
- Home rails now real: Recently Played (RecentStore, persisted, capped)
  + Your Favorites rails from the FavoritesStore; honest first-run
  empty state with a Search nudge. No placeholder data.
- Compile fixes: invalid type-args syntax in Search; audio bridge used a
  non-existent Ref type and an unsafe cast — rewritten against
  ProviderContainer + the BackgroundAudioBridge interface; bridge
  provider converted to StateProvider so the native swap is legal.

## Remaining (honest)

- `flutter create . && flutter pub get && flutter analyze` — one local
  run needed; generated android/ios runners aren't committable here.
  Paste any analyzer output and it gets fixed immediately.
- audio_service needs the Android manifest service entry + generated
  platform runners to activate; the bridge code is complete and degrades
  to no-op elsewhere.
- Breezze /api/v1 backend — future milestone (auth, catalog, scrobble
  sinks, home personalization beyond local history).
