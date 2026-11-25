# Reference ZIP assimilation — `breezze_flutter_app.zip` (25 November 2026)

**Authority:** `MetroKim/Breezze` independent `main` and the open, tested YouTube Music integration PR. This ZIP is a **design reference**, not a second application, replacement architecture, or source of playable songs.

## Provenance and safety scan

- Upload filename: `breezze_flutter_app.zip`.
- SHA-256: `c392682ca93aaeb4d44a07ff25fe4105ad0a7efeb0ad040232925b0b6378362f`.
- Archive inspection: 35 entries (directories included), 19 Dart files, 54,656 uncompressed bytes, ZIP CRC passed and entries inspected for traversal; empty `assets/images/` directory.
- Source README openly labels this as a **UI/UX scaffold** built from a BitChord idea. `lib/data/mock_data.dart` invents songs/artists/lyrics. `lib/state/player_controller.dart` uses a 1-second simulated Timer instead of real audio. `app_shell.dart` has **three** tabs (Home, Search, Library) rather than Breezze's four.
- It depends on `provider`/ChangeNotifier and a separate `ThemeData`; the authoritative Breezze app uses Riverpod, semantic `BzThemeColors`, real audio contracts, NestJS/Prisma, and existing authentication.
- ZIP design theme uses orange ember `#E2672E`, amber `#F2B263`, Fraunces/Inter and dark brown backgrounds. These **are not** approved Breezze runtime brand tokens. Shipping design remains monochrome, white mark on black with optional artwork-driven atmosphere.

## Selective compatibility review

| ZIP source | Decision | Authoritative destination | Reason |
| --- | --- | --- | --- |
| `lib/widgets/artwork_tile.dart` | **Adapt visual behavior only** | `apps/mobile/lib/features/browse/ytmusic_client_screen.dart` | Small rounded art and a subdued gradient fallback are useful; real provider `Image.network` remains authoritative, with cache width and failure states. No fake art/seed identity. |
| `lib/widgets/mini_player.dart` | **UX reference, do not copy** | `apps/mobile/lib/widgets/bz_shell.dart` | Existing mini-player already shares true player state, audio focus, queue and responsive shell. ZIP copies a timer-based controller and different tab bar. |
| `lib/widgets/song_row.dart` | **Reference geometry, not implementation** | Existing Browse/Search/Library/YouTube track rows | Keep consistent artwork/metadata/touch targets, but never wire mock `playSong()` against a YouTube metadata record. |
| `lib/screens/now_playing_screen.dart` | **Visual/reference only** | `apps/mobile/lib/features/player/now_playing_screen.dart` | Breezze has a live rights-aware player, real queue/scrubber, lyrics and background audio integration. No fake seek/skip/shuffle behavior. |
| `lib/screens/lyrics_screen.dart` | **UX reference** | Existing lyrics views and pending translation engine | Synced-line contrast and translation affordance are useful after actual timestamps/translations exist. The ZIP's mock text is not accepted as a licensed lyric. |
| `lib/theme/` | **Do not copy brand/theme** | `packages/design_system/` | Existing design system already has light/dark tokens, 8pt spacing, animation, responsive breakpoints, 44/48pt controls and reduced-motion support. |
| `lib/screens/app_shell.dart` | **Reject** | `BreezzeShell` | Would regress four-tab shell to three tabs, remove Browse, and duplicate the player state. |
| `lib/data/mock_data.dart`, `lib/state/player_controller.dart` | **Reject** | Real Breezze provider/API/rights/just_audio layers | Invented songs, fake lyric translations and timer-playback would misrepresent a working YouTube Music client. |
| `README.md`, `ADDITIONAL.md`, `CODE_OF_CONDUCT.md` | **Archive findings only** | Existing architecture/decision docs | Do not introduce a watch app, Listen Together/social party sessions, or a competing contributor charter without product approval and implementation. |

## Applied UI improvements

The active YouTube Music client now adapts **rounded track artwork and a soft two-tone fallback** using semantic Breezze monochrome colors, bounded image decoding, and explicit image-failure handling. The Explore hero is now an artwork-compatible surface with the existing Breeze mark, clear hierarchy and discovery disclosure. These are incremental source-code changes in PR #67; they are **not** evidence of Figma visual QA or emulator pixel parity until those checks run.

## Non-negotiable ZIP import policy

1. Compare references against the **current main**, not against a legacy fork or a second app shell.
2. Assign each imported feature a single existing owner (screen, shared design component, API adapter, or test).
3. Reject synthetic audio, unauthorized downloads, fake API data, duplicate auth, mock provider services, and incompatible color systems.
4. Adapt only reusable behavior with actual production models and platform-safe paths; use original brand assets and tokens.
5. Add regression tests and pass exact-commit CI before merge. Keep the ZIP outside production runtime and dependency manifests. Any future original uploads are inspected using the same selective policy.

## Pending UI quality gates

Screen-reader traversal/labels, dynamic text scale, image decode pressure, offline artwork placeholders, Home/Browse/Library/Search consistency, hero responsiveness, dark/light screenshot acceptance, reduced-motion state, authentic OAuth consent UI, and Android/iOS visual/emulator checks remain independent requirements. Passing Flutter unit tests is necessary but not equivalent to a complete visual signoff.
