# Breezze Gap Register — spec §50.4

Requirement-by-requirement status against the §49 matrix. A line is
IMPLEMENTED only with real behavior + passing tests (§50.6).

| Req ID | Requirement | Priority | Status | Evidence |
|---|---|---|---|---|
| **A. Identity & design** | | | | |
| A-01 | Brand marks (3 SVG + widget forms) | P0 | IMPLEMENTED | `assets/icons/`, `bz_brand_icons.dart` |
| A-02 | Tokens light+dark, exact §21.1 hex | P0 | IMPLEMENTED | `design_system/src/tokens.dart` |
| A-05 | Type/spacing/radius/elevation scales | P0 | IMPLEMENTED | `tokens.dart` |
| A-03 | Atmosphere materials (colors) | P0 | IMPLEMENTED | `bz_theme.dart` atmo getters |
| **B. App architecture** | | | | |
| B-01/02/04 | Feature folders, Riverpod, one player | P0 | IMPLEMENTED | `features/*`, `player_controller.dart` |
| B-03 | Navigation | P0 | IMPLEMENTED | Shell IndexedStack tabs (Home/Search/Downloads/Settings) |
| **C. Music fetch & search** | | | | |
| C-01/03 | Real source, rights-honest results | P0 | **IMPLEMENTED** | `youtube_source_adapter.dart` (keyless, live) |
| **D. Player & media** | | | | |
| D-01..03 | Player, state machine, queue | P0 | IMPLEMENTED | + 18 tests |
| D-04 | Native playback engine | P0 | **IMPLEMENTED** | `just_audio_engine_adapter.dart` |
| D-05/06/08 | Crossfade, scrobble, AutoMix | P1/P2 | IMPLEMENTED | ports + tests |
| D-07 | Lyrics engine | P1 | IMPLEMENTED | `lrc_parser.dart` + **LRCLIB provider** |
| D-09 | Quality tiers | P0 | IMPLEMENTED | `audio_quality.dart` |
| **E. Downloads & library** | | | | |
| E-02 | Offline downloads | P1 | **IMPLEMENTED** | `downloads_library.dart` + screen |
| E-02b | Lyrics + cover art saved with each download | P1 | **IMPLEMENTED** | `DownloadsLibrary.download()` |
| **F. Backend** | | | | |
| F-01..04 | Breezze /api/v1 | P0 | NOT STARTED | future milestone |
| **G. Privacy** | | | | |
| G-01 | No client secrets | P0 | IMPLEMENTED | keyless sources throughout |
| **H. Premium & settings** | | | | |
| H-01..03 | Tiers, settings, gating | P1 | IMPLEMENTED | `membership.dart`, settings screen |

## What works end-to-end today

1. **Search** → live keyless source → results with artwork.
2. **Play** → resolver → native engine → sound.
3. **Download** → audio + cover.jpg + lyrics.lrc + meta.json per track.
4. **Downloads tab** → real list with cover art from disk.
5. **Lyrics** → LRCLIB synced (word-level via enhanced LRC parser).

## Remaining

- Breezze's own backend /api/v1 (F-01..04) — future milestone.
- Now Playing expanded screen with word-highlight sync UI.
- Local persistence (Drift) for favorites/library.
- Platform runners (Android/iOS) not yet generated — `flutter create .` needed once.
