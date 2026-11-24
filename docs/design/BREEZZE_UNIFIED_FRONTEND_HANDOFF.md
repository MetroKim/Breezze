# Breezze — Unified Mobile UI/UX Handoff

**Status:** Engineering-backed design contract; Figma editor build pending.  
**Canonical Figma destination:** https://www.figma.com/design/ekwtakfmPO7IPjMAbu1iZC  
**Implementation:** `apps/mobile` with `packages/design_system`.  
**Reference uploaded by product owner:** `breezze_flutter(1).zip` → `bitchord_flutter/lib`.  
**Identity:** Breezze, independently developed; preserve upstream license notices where required.

## What is reused from the uploaded reference

The archive is a **small reference UI**, not a functioning streaming application. It includes no real cover-art files (only an empty image directory). The visual ideas are valid; the mock player, mock catalog and unsupported asset lookups are not.

| ZIP screen/component | Existing authoritative Breezze counterpart | Decision |
| --- | --- | --- |
| `theme/mesh_gradient_background.dart` | `packages/design_system/lib/src/bz_ambient_backdrop.dart` | **Adopted**: blurred cover-art atmosphere and layered soft radial washes; continue using semantic light/dark tokens |
| `screens/now_playing_screen.dart` | `apps/mobile/lib/features/player/now_playing_screen.dart` | Preserve real player state, artwork hero, lyric mode and shared controller; use redesigned backdrop |
| `screens/lyrics_screen.dart` | Existing Now Playing synchronized lyrics and LRCLIB flow | Retain timestamp sync, readability and translation eligibility; treat bright-current/dim-inactive line treatment as reference |
| `screens/artist_screen.dart` | `apps/mobile/lib/features/catalog/catalog_detail_screens.dart` | Preserve verified artist data and follow/pin state; adapt cinematic art hierarchy without empty button handlers |
| `widgets/seek_bar.dart` | `apps/mobile/lib/widgets/bz_playback_scrubber.dart` | Preserve real seek state, accessibility and edge cases; avoid second controller |
| `widgets/transport_controls.dart` | Existing Now Playing transport and global controller | Preserve actual play/pause/next/previous engine actions |
| `state/player_state.dart`, `data/mock_catalog.dart` | Existing Riverpod/just_audio, Deezer discovery and authorized playback resolver | **Reject** timer-simulated position, hardcoded tracks and fake stream URLs |

## Design principles — Apple Music-inspired, distinct Breezze brand

- Breezze's own monochrome mark and name; no imported Apple artwork, icons, logos or fonts.
- **Dark:** OLED black ground, white primary typography, artwork-derived subdued ambience, layered frosted lower navigation.
- **Light:** cool gray ground, white surfaces, strong contrast, subdued monochrome accent.
- Large native-feeling title hierarchy; bold editorial artwork; intentionally generous spacing.
- Search bar, cards, tap targets, sheets, overlays and playing controls from shared Breezze token/interaction contracts rather than per-screen hardcoding.
- One globally persistent mini-player over a four-item navigation shell: **Home · Browse · Library · Search**. Full Now Playing presents as a single route and keeps the same playback session.
- Glass overlays are budgeted; do not stack excessive full-screen BackdropFilters on low-end devices. Honor reduced motion and high-contrast preferences.
- 44x44 or larger tappable controls where platform constraints allow; scalable text, semantic labels, keyboard and screen-reader support.

## Full frontend frame map to compose in Figma

1. **Entry and identity:** sign in, email/password, Google, Apple pending state, create account, verify email, recovery, signed-out/error/offline states.
2. **Home:** editorial hero, continue listening, recently played, new releases, recommendations, followed artists, loading/empty/error states.
3. **Browse:** genre/mood editorial cards, charts, new music, verified metadata, source handoff, unavailable-content states.
4. **Library:** songs, albums, artists, playlists, downloads, pinned albums/artists, multi-select add to playlists, library empty/offline states.
5. **Search:** search field, recent searches, suggestions, results by entity type, zero results and error states.
6. **Album and artist details:** cinematic art backdrop and title, metadata, verified artwork hierarchy, playable actions only when authorized, follow and pin actions, release cards and track lists.
7. **Now Playing:** artwork hero and animated transition, source title, transport controls, seek with elapsed/remaining times, lyrics teaser, queue, add to library, more actions, restricted-media explanation.
8. **Lyrics:** synchronized highlighted current line, quieter inactive lines, loading/unsynced/unavailable handling, translation/pronunciation choices if supported.
9. **Playing Next / queue:** reorder, remove, shuffle/repeat, track source diagnostics, no silent playback reset.
10. **Settings / account:** appearance, playback, quality, downloads, language, accessibility, sessions and security, provider status.
11. **Onboarding and Replay:** favorite artists, listening preferences, annual recap cards, authorized sharing.
12. **Responsive forms:** narrow phone, wide phone, tablet and desktop navigation with consistent semantic components.

## Authoritative Flutter layers

```text
apps/mobile/lib/
  widgets/breezze_app_root.dart   # Auth gate + shared MaterialApp
  widgets/bz_shell.dart           # Four tabs + persistent mini-player
  features/home/
  features/browse/
  features/library/
  features/search/
  features/catalog/
  features/player/
  features/settings/
  features/authentication/
packages/design_system/lib/src/
  tokens.dart                     # Color, spacing, radius, motion
  bz_theme.dart                   # Light/dark semantic ThemeData
  bz_ambient_backdrop.dart        # ZIP-inspired mesh-like ambient field
  bz_glass_container.dart         # Shared frosted elements
```

## Verification contract

UI passes only after Flutter analyze, widget tests, responsive screenshot review, semantics audits and phone/tablet emulator acceptance on the exact commit. Figma is **not complete** until these frames are represented as editable layers and inspected. This document is a design handoff, not a false claim that all frames already exist.
