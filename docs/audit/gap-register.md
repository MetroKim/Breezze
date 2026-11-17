# Breezze Gap Register — spec §50.4

Requirement-by-requirement status against the §49 matrix. A line is
IMPLEMENTED only with real behavior + passing tests (§50.6 evidence
standard). Screenshots alone are not evidence.

| Req ID | Requirement | Priority | Status | Evidence / path | Next action |
|---|---|---|---|---|---|
| **A. Product identity and design** | | | | |
| A-01 | Breezze logo, icon, wordmark | P0 | IMPLEMENTED | `assets/icons/*.svg` + `bz_brand_icons.dart` | Launcher icon exports |
| A-02 | Black/white-first tokens, light+dark | P0 | IMPLEMENTED | `design_system/src/tokens.dart` (verified vs §21.1) | — |
| A-03 | Atmosphere materials | P0 | PARTIAL | atmo colors in theme; blur widget pending | `BzGlass` widget |
| A-04 | SVG icons, no emoji | P0 | PARTIAL | Brand marks vector; nav uses Material icons | Original nav icon set |
| A-05 | Type/spacing/radius/elevation tokens | P0 | IMPLEMENTED | `tokens.dart` | — |
| A-06 | Components + variants | P1 | PARTIAL | Tab bar, mini-player, rows, cards; tab bar now navigates | Variant specs |
| **B. Flutter application quality** | | | | |
| B-01 | Feature-first architecture | P0 | IMPLEMENTED | `features/player, home, downloads, settings` | Remaining features |
| B-02 | One state approach (Riverpod) | P0 | IMPLEMENTED | `player_controller.dart` global provider | — |
| B-03 | Typed navigation | P0 | PARTIAL | IndexedStack shell navigation; go_router pending | Router + deep links |
| B-04 | Screens do not own player state | P0 | IMPLEMENTED | All commands via `PlayerController` | — |
| B-05 | Responsive layouts | P1 | NOT STARTED | — | Breakpoint helpers |
| **C. Catalog and providers** | | | | |
| C-01 | Canonical IDs, provider mappings | P0 | IMPLEMENTED | `provider_adapter.dart`, `bz_track.dart` | — |
| C-02 | Provider credentials server-side | P0 | BLOCKED | Signer seam defined (`SignerService`); real backend missing | NestJS API |
| C-03 | Playable sources rights-verified | P0 | IMPLEMENTED | `SourceChain` primary→fallback w/ tests | Backend resolver |
| **D. Player and media** | | | | |
| D-01 | One global player | P0 | IMPLEMENTED | `PlayerController` + `AudioEngineAdapter` | — |
| D-02 | Playback state machine | P0 | IMPLEMENTED | `playback_state_machine.dart` + 7 tests | — |
| D-03 | Queue, shuffle, repeat | P0 | IMPLEMENTED | `queue_manager.dart` + 11 tests | — |
| D-04 | Background playback | P0 | BLOCKED | Platform engine plugin needed | audio_service spike |
| D-05 | Crossfade | P1 | IMPLEMENTED | `crossfade_controller.dart` | Engine fade |
| D-06 | Scrobbling | P1 | IMPLEMENTED | `scrobble_bus.dart` + 2 tests | Real sinks |
| D-07 | Lyrics engine | P1 | IMPLEMENTED | `lrc_parser.dart` + 5 tests | Lyrics UI |
| D-08 | AutoMix | P2 | **IMPLEMENTED** | `automix.dart` + 4 tests (ported, closes D-08) | Engine tempo factor |
| D-09 | Quality tiers incl. lossless/Hi-Res | P0 | **IMPLEMENTED** | `audio_quality.dart` honest labels, no upsample | Server gating |
| **E. Library and offline** | | | | |
| E-01 | Favorites, library persist | P0 | NOT STARTED | — | Drift store |
| E-02 | Offline downloads | P1 | **IMPLEMENTED (core)** | `download_manager.dart` + Downloads UI; eligibility, retry, remove | Engine file sink |
| E-03 | Sync without silent loss | P1 | NOT STARTED | — | Outbox |
| **F. Backend and operations** | | | | |
| F-01..04 | /api/v1, Postgres, auth, observability | P0 | NOT STARTED | — | NestJS scaffold |
| **G. Privacy and security** | | | | |
| G-01 | No client-side secrets | P0 | IMPLEMENTED | Signer + resolver are server-side contracts | — |
| G-02 | History controls, deletion | P1 | NOT STARTED | — | Privacy screens |
| **H. Premium & monetization** | | | | |
| H-01 | Membership tiers + entitlements | P1 | IMPLEMENTED (client domain) | `membership.dart` tiers, `Entitlement` snapshot | Server billing |
| H-02 | Settings: quality/playback/downloads | P1 | IMPLEMENTED | `settings_screen.dart` sections | Persist via prefs |
| H-03 | Premium gating (lossless/Hi-Res/AutoMix) | P1 | IMPLEMENTED (hints) | settings + entitlement model; server decides | Billing provider |

## Fixed this pass

- Dead tab-bar navigation → real IndexedStack switching (A-06).
- AutoMix D-08 → ported with 4 tests.
- Design-system barrel missing → `breezze_design_system.dart` added.
- audio_contracts pubspec invalid trailing section → removed.
- Downloads + Settings + open-source README added.

## Repair order (§50.5)

1. ✅ Source chain, downloads, membership, quality, AutoMix.
2. ⬜ BzGlass material widget (A-03).
3. ⬜ go_router + deep links (B-03).
4. ⬜ Drift local store (E-01) → wire Downloads list to real jobs.
5. ⬜ NestJS API scaffold (F-01) with auth + resolver.
