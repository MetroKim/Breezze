# Breezze frontend — no-skips polish and acceptance matrix

**Canonical implementation:** `apps/mobile/lib` and `packages/design_system` in the independent `MetroKim/Breezze` repository.

**Design reference:** `docs/design/BREEZZE_UNIFIED_FRONTEND_HANDOFF.md` and the supplied Breezze Flutter ZIP. Preserve the real playback controller, Deezer catalog, authentication, Cloudflare rights gate and Supabase state. Do **not** import mock songs, timer playback or unlicensed audio URLs.

**Status rule:** A box remains unchecked until the *specific* screen/state is exercised at the latest main commit with evidence. A passing analyzer or generic widget test does not by itself prove visual polish.

## Universal design acceptance — every screen, without exceptions

- [ ] Breezze branding, typography, spacing, semantic surface and icon colors consistent in dark and light modes
- [ ] Narrow phone (320 logical px), standard phone, large phone, tablet and desktop widths reviewed for overflow and content density
- [ ] Text scaling at 100%, 150% and 200% without loss of labels, controls or reachable actions
- [ ] Screen-reader names/roles, logical focus order, visible keyboard focus and 44 px preferred targets verified
- [ ] Reduced-motion/high-contrast rendering, dark OLED contrast, and transient screen transitions checked
- [ ] Loading, empty, offline, unauthorized, permission-denied, network-error and retry states checked wherever applicable
- [ ] Artwork loading errors, image aspect/cropping, localization and very long track/artist/playlist names checked
- [ ] Semantic actions and navigation actually work; no placeholder onTap, fake data or false playback affordances
- [ ] Screenshot/golden or manual visual capture archived alongside exact Git SHA and device size
- [ ] Android and iOS emulator acceptance on the same SHA, including interactive gestures, rotation and back navigation

## Surface inventory and acceptance owners

| Surface | Authoritative Flutter source | Specific acceptance | Verification |
| --- | --- | --- | --- |
| App root, signed-out gate | `widgets/breezze_app_root.dart` | Auth-before-home; restoration; correct appearance and onboarding overlay | Pending screen QA |
| Authentication and recovery | `features/authentication/auth_screen.dart` | Email/password, Google, Apple pending/disabled, verification, errors, password recovery | Pending screen QA |
| First-run onboarding | `features/onboarding/` | Favorite artist entry, region selection, progress, skip and close | Pending screen QA |
| Four-tab navigation | `widgets/bz_shell.dart` | Home/Browse/Library/Search, selected tabs, desktop sidebar, bottom glass bars | Pending screen QA |
| Global mini-player | `widgets/bz_shell.dart` | Real player state, preview rules, swipe/open, live scrubber and queue | Pending screen QA |
| Home | `features/home/home_screen.dart` | Personalized rails, Deezer previews, recently played, replay, first-run and errors | Pending screen QA |
| Browse and charts | `features/browse/browse_screen.dart` | Genres, editorial cards, chart source, navigation and fetch errors | Pending screen QA |
| YouTube Music metadata | `features/browse/ytmusic_client_screen.dart` | Track rights explanations and official-player handoff, never fake audio | Pending screen QA |
| Library and downloads | `features/library/library_screen.dart` and `features/downloads/` | Saved songs/albums/artists, pinned content, downloads, offline sync | Pending screen QA |
| Playlist creation/details | `features/library/playlist_detail_screen.dart` and `add_to_playlists_sheet.dart` | Add/remove/reorder, multiple destinations, cloud conflict/empty/error | Pending screen QA |
| Search | `features/search/search_screen.dart` | Typeahead, history, categorized results, zero results, keyboard | Pending screen QA |
| Album and artist detail | `features/catalog/catalog_detail_screens.dart` | Cinematic art, follow, save, verified catalog, readable tracks | Pending screen QA |
| Now Playing | `features/player/now_playing_screen.dart` | Artwork, queue, controls, audio source restrictions, seeking, timers | Pending screen QA |
| Synced lyrics | `features/player/now_playing_screen.dart` | Current-line focus, unsupported lyrics, scroll, language options | Pending screen QA |
| Video | `features/video/` | Official embedded-video controls, navigation, no confusing audio-only claims | Pending screen QA |
| Settings | `features/settings/settings_screen.dart` | General, language, visual appearance, playback, quality, downloads, privacy | Pending screen QA |
| Account and sessions | `features/settings/account_screen.dart` | Profile, identity, security, session, logout confirmation | Pending screen QA |
| Help and support | `features/settings/help_support_screen.dart` | Reachability and readable error/help explanations | Pending screen QA |
| Notifications | `features/notifications/` | Permission state, settings route, retry and no fabricated messages | Pending screen QA |

## Implemented foundation, evidence still required

- [x] Monochrome OLED and cool-light semantic palette defined in `tokens.dart`
- [x] Artwork-derived mesh atmosphere imported *without* replacing the real player in `bz_ambient_backdrop.dart`
- [x] Shared type, AppBar, button, input, card, dialog, bottom-sheet and snackbar geometry implemented on the frontend-foundations branch
- [x] Common minimum touch target styles and keyboard-focused input outlines implemented on the frontend-foundations branch
- [x] Shared glass high-contrast/reduced-motion fallbacks added, with regression tests
- [x] Home account avatar enlarged and given an accessible name/tooltip
- [ ] Latest-head Flutter analysis and all widget tests pass
- [ ] Branch merged into `main`
- [ ] All individual visual states and emulators signed off

**Do not mark the frontend fully polished until every universal criterion and relevant surface acceptance is checked with actual evidence.** This matrix is the no-skips contract, not a claim of completion.
