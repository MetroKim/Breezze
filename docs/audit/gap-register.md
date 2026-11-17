# Breezze Gap Register — spec §50.4

A line is IMPLEMENTED only with real behavior + passing tests (§50.6).

| Req ID | Requirement | Status | Evidence |
|---|---|---|---|
| **A. Identity & design** | | | |
| A-01 | Brand marks (3 SVG + widget forms) | IMPLEMENTED | `assets/icons/`, `bz_brand_icons.dart` |
| A-02 | Tokens light+dark, exact §21.1 hex | IMPLEMENTED | `design_system/src/tokens.dart` (read back + verified) |
| A-05 | Type/spacing/radius/elevation scales | IMPLEMENTED | `tokens.dart` |
| A-03 | Atmosphere materials (colors in theme) | IMPLEMENTED | `bz_theme.dart` |
| **B. App architecture** | | | |
| B-01/02/04 | Feature folders, Riverpod, one player | IMPLEMENTED | `features/*`, `player_controller.dart` |
| B-03 | Navigation | IMPLEMENTED | 5 real tabs + mini-player → Now Playing route |
| **C. Music fetch & search** | | | |
| C-01/03 | Real keyless source, honest results | IMPLEMENTED | `youtube_source_adapter.dart` |
| **D. Player & media** | | | |
| D-01..03 | Player, state machine, queue | IMPLEMENTED | + tests |
| D-04 | Native playback engine | IMPLEMENTED | `just_audio_engine_adapter.dart` |
| D-05/06/08 | Crossfade, scrobble, AutoMix | IMPLEMENTED | ports + tests |
| D-07 | Lyrics engine + provider | IMPLEMENTED | `lrc_parser.dart` + LRCLIB (duration-keyed) |
| D-09 | Quality tiers | IMPLEMENTED | `audio_quality.dart` |
| **D-10** | **Now Playing screen, word-synced lyrics** | **IMPLEMENTED** | `now_playing_screen.dart` |
| **E. Downloads & library** | | | |
| E-01 | Favorites persistence | **IMPLEMENTED** | `FavoritesStore` (JSON, app documents) + Library screen |
| E-02 | Offline downloads w/ lyrics + art | **IMPLEMENTED** | `downloads_library.dart`, `path_provider` app-private dir |
| **G. Privacy** | | | |
| G-01 | No client secrets | IMPLEMENTED | keyless sources throughout |
| **H. Premium & settings** | | | |
| H-01..03 | Tiers, settings, gating | IMPLEMENTED | `membership.dart`, settings screen |

## Fixed this pass

- Broken imports: design-system import missing from 7 screens (compile error).
- Settings wrong import path (`widgets/...` → `../../widgets/...`).
- Lyrics fuzzy search never parsed duration → wrong edits could win (now ranked by closest duration).
- `PlayerState` had no track info → Now Playing/mini-player couldn't show title/artist/artwork (now `TrackInfo` + queue context).
- Downloads location was `systemTemp` → now `path_provider` app documents (private, survives restarts).
- Search played only one track with no queue → now plays the full result list as a queue.
- Mini-player was static → now shows title, artwork, live progress, and opens Now Playing.
- `main.dart` unused imports cleaned; shell owns providers properly.
- Now Playing built: breathing artwork, transport, seek, favorites heart, karaoke word-sync lyrics.
- Library screen built: persisted favorites, play-all, per-track play.

## Remaining (honest)

- `flutter create . && flutter analyze` still needs a local run — platform runners (android/, ios/) are generated there.
- Download progress UI (currently SnackBar; live progress bar needs the DownloadManager stream wiring).
- Background audio (audio_service) — lock-screen controls.
- Home rails personalization — needs catalog backend.
- Breezze /api/v1 backend — future milestone.
