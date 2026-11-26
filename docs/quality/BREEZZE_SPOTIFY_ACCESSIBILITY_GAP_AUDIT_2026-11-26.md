# Breezze — Spotify documentation–informed accessibility gap audit

**Date:** 26 November 2026  
**Scope:** Flutter app quality/accessibility and Spotify-data attribution. **Out of scope:** redesigning or replacing the Apple Music–inspired Breezze interface.

## Source references and non-negotiable design rule

- [Spotify Accessibility Guidelines](https://developer.spotify.com/documentation/accessibility) — alternative text, semantic controls, 44pt iOS / 48dp Android targets, 4.5:1 text / 3:1 essential UI contrast, keyboard focus, meaningful headings, multimodal status and respectful animation.
- [Spotify Design & Branding Guidelines](https://developer.spotify.com/documentation/design) — attribution, source links, developer content usage restrictions, authorized branding. These are **integration obligations**, not instructions to copy the Spotify application interface.
- [Spotify Developer Policy](https://developer.spotify.com/policy) — verify whether displaying Spotify catalog metadata alongside competing music services is permitted before a production release.
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/) — additional accessibility acceptance criteria independent of visual brand.

**Identity preserved:** Breezze's original design tokens, light/dark surfaces, album-art hero, typography, four tabs, custom filter capsules, glass surfaces and Now Playing layout. No Spotify font, component geometry, green accent system, navigation, layouts, or logo is imported as the Breezze brand. Where Spotify content is rendered, add only legally required source attribution after partner/legal review.

## Evidence-backed issue and fix matrix

| Priority | Gap / potential exclusion | WCAG area | Implemented in code | Verification status |
| --- | --- | --- | --- | --- |
| P0 | The big Now Playing play/pause was a gesture-only circle without a labeled semantic action or keyboard activation | 2.1.1, 2.5.8, 4.1.2 | Replace `GestureDetector` with focusable circular Material `InkWell`, accessible Play/Pause label and tap action. Shape, color, size stay original | Source changed; Flutter + VoiceOver/TalkBack tests pending |
| P0 | Mini-player scrubber supported pointer drags and screen-reader increment/decrement but not physical keyboard navigation | 2.1.1, 2.4.7, 4.1.2 | Add keyboard focus, visible accent focus border, Arrow ±5%, Home and End. Existing tap/drag and percentage semantics remain | Regression test added; CI and device checks pending |
| P1 | Search had only a hint and lacked an explicit accessible search name; headings were visually styled but not screen-reader headings | 1.3.1, 2.4.6, 3.3.2 | Search semantic label, Search/Artists/Songs/Similar searches heading roles; retain existing design and conditional filters | Widget test added; CI pending |
| P1 | Search loading skeletons, empty results and errors were not consistently announced as status | 4.1.3 | Loading/empty/error live-region announcements; decorative loading skeleton rows excluded from accessibility tree | Source changed; auditory timing must be reviewed on devices |
| P1 | Artist imagery repeated adjacent text for assistive-technology users; artist section heading navigation was incomplete | 1.1.1, 1.3.1 | Meaningful separate semantic labels for hero portrait / album cover; decorative row art hidden; artist/album section headings and error live region | Widget assertions added; manual screen-reader review pending |
| P1 | Animated karaoke lyric transitions ignored the system reduced-animation preference; low-opacity inactive lyrics can be difficult to read | 1.4.3, 2.2.2, 2.3.3 | Respect reduced motion for lyric text transitions; in OS high-contrast mode preserve readability using full-opacity inactive text and weight. Synced lines offer labeled seek-to-lyric actions | Source changed; high-contrast and TalkBack/VoiceOver validation pending |
| P1 | Palette contrast could silently regress during design polish | 1.4.3, 1.4.11 | Add light/dark contrast regression tests using the **unchanged Breezze colors**. Light secondary text is approx. **4.66:1 on #F5F5F7**; dark secondary text is approx. **6.67:1 on #2C2C2E**. Existing focus accents exceed 3:1 on main surfaces | Mathematical token check performed; automated Dart test created, CI pending |
| P1 | Larger-text support should not be assumed from one phone-size screenshot | 1.4.4, 1.4.10 | Add 200% text-scaling / selected-state test for the existing filter pill; base visual component already has 48dp minimum height | Test created; **complete app 200%/320dp reflow still outstanding** |
| P1 | Potential keyboard/assistive tech gaps in unreviewed screens, dialogs, queue reorder, authentication and dynamic content | 2.1.1, 2.4.3, 4.1.2 | Existing Material widgets and buttons provide an initial baseline; add full platform audit backlog | **Open — cannot claim app-wide WCAG AA compliance** |
| P0 | Spotify material has specific attribution and cross-service-use restrictions | Brand/partner compliance | Existing source links remain; production Spotify+Deezer artist-page mixing stays approval-gated | **Open — confirm exact approved attribution assets/format and partner terms before production** |

### Contrast methodology

For two opaque colors, the ratio is `(Lmax + 0.05)/(Lmin + 0.05)`, where `L` is WCAG relative luminance. The test compares Breezze `text1` and `text2` against its `background`, `surface1`, `surface2`, and `elevated` semantic tokens, and verifies a 3:1 focus-accent contrast against its background / primary surface. This tests **token pairs only**; artwork overlays, dynamically tinted glass, disabled text, gradients, live album images, and third-party embedded player elements still require rendered-device contrast inspection.

### Required validation before acceptance

1. Run `flutter analyze` and `flutter test` in `apps/mobile`, including `test/search_typeahead_test.dart`, `test/spotify_artist_page_test.dart`, `test/bz_playback_scrubber_test.dart` and `test/features/player/now_playing_screen_test.dart`.
2. Run `flutter test` in `packages/design_system` and verify the contrast, reduced-motion, high-contrast glass and 200%-text tests.
3. On iOS simulator with VoiceOver and Android emulator with TalkBack: navigate tabs and search, open an artist, read artist headings and hero labels, activate play/pause, change position, inspect queued songs and open/close dialogs.
4. On desktop/emulator with a physical keyboard: Tab and Shift+Tab through relevant controls; Space/Enter on play, arrows and Home/End on the mini scrubber; confirm visible focus and no keyboard traps.
5. At 200% font scale and narrow width, inspect full Search, Artist, Authentication, Library and Now Playing views for clipping, overlapping controls and inaccessible actions. Also test dark/light, high contrast, reduced animation, offline/errors and RTL/localization.
6. Audit full app for contrast over dynamic artwork/blur, mislabeled icon buttons, semantics announcements that occur too frequently, inaccessible drag/reorder-only tasks and uncaptained video/lyrics content.
7. Verify Spotify required attribution and catalog-content usage rights before releasing any cross-service metadata experience. Metadata is **not** a native audio streaming or downloading grant.

**Status policy:** Commit to GitHub is **implementation**, not acceptance. Do not mark any CI, emulator, screen-reader or partner-compliance item PASS until corresponding evidence exists. Keep these tasks in the engineering quality-gate backlog without changing Breezze's product visual language.
