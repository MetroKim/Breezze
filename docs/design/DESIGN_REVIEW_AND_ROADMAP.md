# Breezze UI/UX review and implementation plan

Review basis: current Flutter source on `main` (Home, Browse, Radio, Library, Search, Now Playing, shell and design-system package) plus the supplied music-app interaction catalogue. This is a source-code review, not a screenshot/device usability test.

## Executive assessment

Breezze already has a recognizable foundation: semantic light/dark tokens, a consistent spacing/type/radius/motion scale, custom vector brand marks, an artwork-led Now Playing backdrop, a mini-player, persistent tab state through an IndexedStack, and real-data/empty/error states.

The current UI is a functional early product shell, not yet a complete premium music-service experience. The largest gap is breadth and hierarchy of the product surfaces—not a need for more gradients, glass or visual decoration. Keep the existing visual identity and improve navigation, content architecture, component consistency and accessibility.

## What is already working

- `packages/design_system`: central `BzThemeColors` extension and `BzColorsLight/Dark`, spacing, radius, elevation, motion and type tokens.
- `BzGlassContainer`: one reusable glass material instead of one-off blur implementations.
- `BzAmbientBackdrop`: artwork-led player atmosphere.
- `bz_brand_icons.dart`: original Breezze vector-painted brand marks.
- `HomeScreen`: recently played and favorites are persisted data, with an honest first-run empty state.
- `SearchScreen`: recent query history, stale-request protection, loading/error/empty states and real source results.
- `RadioScreen`: honest station/schedule UI; it does not pretend station playback works before the stream is connected to the audio engine.
- `NowPlayingScreen`: artwork, transport controls, seek, favorites and synced/plain lyrics.
- `BzHome`: IndexedStack preserves tab screen state and the mini-player remains available above navigation.

## Priority findings

### P0 — Navigation architecture and reachability

Current shell exposes seven horizontally scrollable text pills: Home, Browse, Radio, Library, Search, Downloads and Settings. The supplied product catalogue defines five primary destinations with persistent icon navigation: Home, Browse, Radio, Library and Search.

Recommended change:
- Make the five music destinations the primary navigation.
- Move Downloads into Library as a filter/section, while retaining a direct route from download actions.
- Move Settings to a profile/account destination or an overflow destination reachable from the top-level shell.
- Use a responsive navigation rail/sidebar on wider layouts; do not stretch the mobile bottom bar across desktop.
- Use a consistent icon family (prefer SVG/Lucide-style outline icons) and provide selected, unselected, pressed, disabled and focus states.
- Keep the mini-player visually attached to navigation without obscuring scroll content or system insets.

Acceptance: all five primary destinations are reachable in one tap, no horizontal scrolling is needed to discover core tabs, state is preserved when switching tabs, and every icon has a semantic label.

### P1 — Home / Listen Now content hierarchy

Current Home has a brand logo, title/tagline, Recently Played and Favorites rails, and a first-run card. It does not yet provide the broader Listen Now hierarchy described in the supplied catalogue.

Recommended sequence (render a section only when its real data source exists):
1. Compact top bar with profile/account action.
2. Listen Now title and a small contextual greeting only if the data exists.
3. Recently Played.
4. Real personalized mix/recommendation rail when backend recommendation data exists.
5. New or featured releases only when editorial/catalog endpoints exist.
6. Favorites / saved content.
7. Replay/insights only after listening analytics exist.

Use artwork-led cards with consistent aspect ratios, subtle borders and typography. Avoid large empty hero panels and placeholder content. The first-run state should lead directly into Search and explain what will populate Home.

### P1 — Library information architecture

Current Library is a Favorites-only screen. The product catalogue expects Playlists, Artists, Albums, Songs and Downloaded, with optional Genres/Compilations and editable section visibility.

Recommended implementation order:
1. Library landing page with section selector: Playlists, Artists, Albums, Songs, Downloaded.
2. Favorites as a first-class saved collection.
3. Playlist creation and detail page only when playlist APIs/local persistence support create, rename, reorder and delete.
4. Artist/album detail views backed by canonical catalog data.
5. Downloads section backed by verified offline file state, not just an in-progress indicator.
6. Section customization after the base sections are real.

Do not show empty tabs that imply unsupported data. Explain unavailable capabilities rather than rendering fake counts or demo rows.

### P1 — Search and Browse differentiation

Current Search performs a provider search and shows recent searches/results. Browse is a genre chip row backed by the same source search. These two destinations currently overlap.

Recommended distinction:
- Search: global query input, recent searches, categorized result groups (tracks/albums/artists/playlists) as those result types become available, and a Library-only scope when local catalog indexing exists.
- Browse: discovery landing page with genre/mood entry points first; then New Releases, Trending, Charts, Coming Soon, Music Videos and Concerts only when backed by reliable endpoints.
- Never label provider search ranking as an official chart or editorial recommendation.
- Add explicit result-type icons and contextual actions (play, add/save, download, share) only when the action is supported.

### P2 — Now Playing and queue

The current player has strong foundations: ambient artwork, animated artwork, seek, shuffle/repeat, favorite and lyrics. The supplied catalogue describes additional interaction surfaces not yet visible in this screen.

Recommended next:
- Add an accessible Playing Next sheet with current queue, remove, reorder, clear and continue-playing semantics.
- Show current queue context and source where known.
- Add lyrics expand/collapse and reliable track-change reload/cancellation.
- Add output-route selection only when the platform/audio integration can enumerate real devices.
- Add share and item action menus with working callbacks.
- Keep artwork breathing motion subtle and disabled when `MediaQuery.disableAnimations` is true.
- Ensure the progress slider remains usable with screen readers and large text.

Do not add karaoke vocal separation, Automix, AirPlay/SharePlay or lossless badges unless the underlying audio/provider capabilities actually exist.

### P2 — Radio

Current Radio correctly presents stations and schedules without fake play controls. Preserve that honesty. The next product step is a real station stream contract integrated with the same playback lifecycle, background audio, interruptions, lock-screen metadata and error handling. Until then, station detail should remain informational and should not display a misleading Play button.

### P2 — Visual and accessibility consistency

- Standardize icons; current screens mix Material Icons with custom brand marks. The product direction calls for dedicated vector icons, not emoji.
- Use a single track-row component for Search, Browse, Library and queue so artwork, title, artist, metadata, trailing actions and touch behavior stay consistent.
- Use cached/resized artwork with stable placeholders and error states; avoid repeated direct network image implementations with different sizes.
- Use consistent list insets, row heights, card radii, separators and action placement.
- Give every tappable surface tooltip/semantic labels and a comfortable touch target.
- Respect text scaling, high contrast, focus traversal, reduced motion and screen-reader order.
- Avoid excessive BackdropFilter layers. Reserve glass for floating navigation, mini-player and sheets; keep content surfaces mostly opaque.
- Add responsive layouts for tablet/desktop instead of relying on the mobile floating navigation treatment.

## Source-level issues to verify/fix

1. `BzGlassContainer` currently treats `MediaQuery.boldText` as a reason to remove glass and describes the fallback as reduced-transparency support. Bold text is not a reduced-transparency setting. Revisit this condition and document the actual accessibility behavior accurately.
2. `NowPlayingScreen` loads lyrics in `initState` from the then-current track. Verify lyrics are refreshed when the current track changes while the screen remains mounted; guard against stale async lyric responses.
3. Home's track cards use a custom GestureDetector press lifecycle. Ensure cancel, accessibility semantics, keyboard/focus behavior and tap activation are covered by widget tests.
4. The seven-item shell is horizontally scrollable and uses text-only pills. This is a discoverability and responsive-navigation risk.
5. Network artwork loading is implemented repeatedly with `Image.network`. Standardize caching, memory sizing, placeholders and failure handling.
6. Verify the shell's mini-player/tab bar safe-area and content-bottom padding on small devices, landscape, large text and devices with gesture navigation.

## Design implementation phases

### Phase A — Foundations
- Establish shared icon wrapper and SVG/icon asset policy.
- Establish reusable artwork, track row, section header, empty state, loading skeleton, error state and action menu components.
- Add component gallery/golden tests for light and dark themes.
- Add accessibility widget tests for labels, touch targets and text scaling.

### Phase B — Product shell
- Replace seven text pills with five primary icon destinations.
- Add adaptive rail/sidebar behavior for larger widths.
- Relocate Downloads and Settings without removing functionality.
- Keep mini-player persistent and safe-area aware.

### Phase C — Core music surfaces
- Expand Home with real data-backed sections.
- Build Library section navigation and canonical item detail pages.
- Separate Search from Browse.
- Build queue and lyrics lifecycle behavior into Now Playing.

### Phase D — Discovery and social features
- Add charts, moods, release calendars, music videos, concerts, artist follow, playlist collaboration and sharing only as their APIs and rights/permissions become available.
- Add replay/insights after reliable listening analytics exist.

## Definition of done

- Every visible action works; no decorative buttons with empty callbacks.
- Every visible data section is backed by a real source or has a clear empty state.
- Light and dark themes are visually coherent.
- Navigation is discoverable without horizontal scrolling on phones.
- Artwork is cached/resized and does not trigger excessive rebuilds or memory use.
- Animations respect reduced-motion preferences.
- All interactive controls have semantic labels and usable touch targets.
- Widget/golden tests cover Home, Browse, Search, Library, Radio, Now Playing, mini-player and shell in light/dark themes.
- `flutter analyze` and `flutter test` pass before merge.

## Related references

See [REFERENCE_REPOSITORIES.md](REFERENCE_REPOSITORIES.md) for the curated external code/design references and the rules for adapting them safely.
