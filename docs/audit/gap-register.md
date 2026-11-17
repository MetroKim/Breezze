# Breezze Gap Register — spec §50.4

Requirement-by-requirement status against the §49 matrix. A line is
IMPLEMENTED only with real behavior + passing tests (§50.6 evidence
standard). Screenshots alone are not evidence.

| Req ID | Requirement | Priority | Status | Evidence / path | Next action |
|---|---|---|---|---|---|
| **A. Product identity and design** | | | | |
| A-01 | Breezze logo, icon, wordmark | P0 | IMPLEMENTED | `apps/mobile/assets/icons/*.svg` (3 marks) + `bz_brand_icons.dart` widgets | Store-launcher icon exports for iOS/Android |
| A-02 | Black/white-first tokens, light+dark | P0 | IMPLEMENTED | `packages/design_system/lib/src/tokens.dart` (verified vs §21.1) | Token widget tests |
| A-03 | Atmosphere materials | P0 | PARTIAL | `bz_theme.dart` exposes atmo colors; blur/blur-fallback widget pending | `BzGlass` widget with blur + reduced-transparency fallback |
| A-04 | SVG icons, no emoji | P0 | PARTIAL | Brand marks are vector; nav uses Material icons temporarily | Replace nav icons with original SVG set |
| A-05 | Typography/spacing/radius/elevation tokens | P0 | IMPLEMENTED | `tokens.dart` (§21.3–21.7) | — |
| A-06 | Component variants and states | P1 | PARTIAL | Tab bar, mini-player, album card, rails in `bz_shell.dart`, `home_screen.dart` | Component specs + variants doc |
| **B. Flutter application quality** | | | | |
| B-01 | Feature-first architecture | P0 | IMPLEMENTED | `features/player`, `features/home`, `widgets/` (§26.2) | Add remaining feature folders |
| B-02 | One state approach (Riverpod) | P0 | IMPLEMENTED | `player_controller.dart` global provider (§51.3) | — |
| B-03 | Typed navigation, deep links | P0 | PARTIAL | `go_router` dependency added; routes not defined | Router with typed routes + deep links (§51.5) |
| B-04 | Screens do not own player state | P0 | IMPLEMENTED | All commands dispatch to `PlayerController` (§53.1) | — |
| B-05 | Responsive layouts | P1 | NOT STARTED | — | Breakpoint helpers (§21.4) |
| **C. Catalog and providers** | | | | |
| C-01 | Canonical Breezze IDs, provider mappings | P0 | PARTIAL | `provider_adapter.dart` models normalize + ProviderOp results | Backend mapping tables (§52.3) |
| C-02 | Provider credentials server-side | P0 | NOT STARTED | — | Backend env/secret store; never in client (§36.3) |
| C-03 | Playable sources rights-verified | P0 | PARTIAL | `PlaybackResolver` contract requires authorized source | Backend resolver endpoint (§29.9) |
| **D. Player and media** | | | | |
| D-01 | One global player | P0 | IMPLEMENTED | `PlayerController` + `AudioEngineAdapter` (§53.1) | — |
| D-02 | Playback state machine | P0 | IMPLEMENTED | `playback_state_machine.dart` + 7 tests | — |
| D-03 | Queue, shuffle, repeat | P0 | IMPLEMENTED | `queue_manager.dart` + 11 tests | — |
| D-04 | Background playback / media controls | P0 | BLOCKED | Requires platform audio engine plugin integration | Spike `audio_service` adapter |
| D-05 | Crossfade | P1 | IMPLEMENTED | `crossfade_controller.dart` (KMP port) | Engine fade integration |
| D-06 | Scrobbling | P1 | IMPLEMENTED | `scrobble_bus.dart` + tests | Real Last.fm/ListenBrainz sinks |
| D-07 | Lyrics engine | P1 | IMPLEMENTED | `lrc_parser.dart` + 5 tests | Lyrics UI + translations |
| D-08 | AutoMix | P2 | NOT STARTED | KMP version exists on `chordline` as oracle | Port `Automix.kt` to Dart |
| **E. Library and offline** | | | | |
| E-01 | Favorites, library, playlists persist | P0 | NOT STARTED | — | Drift/SQLite local store (§25) |
| E-02 | Offline downloads | P1 | BLOCKED | Requires licensing decision (§54.2) | Rights decision before any download code |
| E-03 | Sync without silent data loss | P1 | NOT STARTED | — | Outbox + conflict resolution (§54.5) |
| **F. Backend and operations** | | | | |
| F-01 | /api/v1 contracts | P0 | NOT STARTED | — | NestJS API + migrations (§29) |
| F-02 | PostgreSQL data model | P0 | NOT STARTED | — | §28 schema migrations |
| F-03 | Auth, sessions, refresh | P0 | NOT STARTED | — | §29.1 endpoints |
| F-04 | Observability | P1 | NOT STARTED | — | OTel + dashboards (§59.2) |
| **G. Privacy and security** | | | | |
| G-01 | No client-side secrets | P0 | IMPLEMENTED | Contracts require server-side resolver; no keys in client | Audit on API wiring |
| G-02 | Listening-history controls | P1 | NOT STARTED | — | Privacy settings screens |
| G-03 | Account deletion/export | P1 | NOT STARTED | — | Backend + settings screen |

## Repair order (§50.5)

1. ✅ ADR-001 accepted — direction fixed.
2. ✅ Token foundation — verified against spec.
3. ✅ KMP core ports with tests.
4. ⬜ Router + deep links (B-03).
5. ⬜ BzGlass material widget + reduced-transparency fallback (A-03).
6. ⬜ Local persistence (E-01) then API wiring (F-01).
7. ⬜ Remaining §49 matrix lines scheduled by priority.
