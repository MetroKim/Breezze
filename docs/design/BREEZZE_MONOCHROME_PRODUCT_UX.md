# Breezze — Monochrome Product UI & UX Contract

## Source of truth

The app identity comes from the user-provided Breezze brand archive, not an approximate B-note:
- `assets/icons/breezze-app-icon.svg`: 1024-square black (#050505), rounded 218-unit radius, exact white custom mark.
- `assets/icons/breezze-symbol-white.svg` and `breezze-symbol-black.svg`: original editable vector paths; all screen marks are theme-tinted through `BzBnoteMark`.
- `assets/icons/breezze-logo-white.svg` and `breezze-logo-black.svg`: exportable official vector lockups. In Flutter, `BzRibbonLogo` combines the exact vector symbol with accessible editable wordmark text because SVG text rendering varies across operating systems.

The mark is **not** a replacement for play, shuffle, volume or navigation controls. Those remain specific SVG affordance icons in `BzSvgIcon` or `assets/icons/` for comprehension and accessibility.

## Color tokens across every screen

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | #F6F6F8 | #050505 |
| Primary surface | #FFFFFF | #171719 |
| Secondary surface | #EFEFF2 | #252528 |
| Main text / active monochrome accent | #111114 | #FFFFFF |
| Secondary text | #57575D | #B6B6BD |
| Edge | translucent black 7% | translucent white 10% |

Dynamic album artwork can retain its *own* artwork colors, but Breezze chrome, controls, navigational states, sheets, system status and interaction adornments do not introduce blue or purple brand accent colors. Errors, warnings and success can still use deliberately distinct **semantic** colors for accessibility, not as brand decoration.

All themes use the same shared `bzLightTheme()` / `bzDarkTheme()` and `BzThemeColors`/Liquid Glass tokens. Material button, text, input, nav, slider, switch, card and sheet defaults must inherit them. In Settings, System/Light/Dark is a functional preference persisted by `bzThemePreferenceProvider` and honored by the top-level `MaterialApp`.

## Screen behavior and content hierarchy

1. **Sign in / registration:** First-party Breezze mark; Google and Apple OAuth only when verified and credentialed; email/password and admin MFA never break. No fake provider-success states.
2. **Listen Now / Home:** quiet Breezze wordmark, greeting, compact recently played shortcuts, "Made for You" and other populated rails, gentle fallbacks for missing art and clearly labeled first-run discovery prompts. No invented songs in the live app.
3. **New / Browse:** large editorial title, focused genre/category filters, grid that adapts from two columns on phones to 3–4 on tablets/desktop, chart/release/video navigation and rights-aware playback.
4. **Radio:** station list and curated live radio surfacing only real sources that permit playback. Unavailable stations explain why, rather than looking playable.
5. **Library:** dedicated filters for Songs, Artists, Albums, Playlists and Downloads; owner-scoped cloud saved albums and durable offline queue; Edit and add actions remain reachable.
6. **Search:** top search input, recent queries, categories, source-correct result types, explicit distinction between catalog discovery metadata and actual playable tracks.
7. **Mini-player / Now Playing:** persistent, narrow pill with actual artwork/track metadata, play/pause/next, a real seekable progress strip, immersive album-art viewport, lyrics and queue accessible without duplicating audio sessions.
8. **Video:** sanctioned embedded video player where allowed, with explicit unavailable states; no hidden third-party source bypass.
9. **Account / Profile:** personal account data, saved library, playback history, sessions, security, and sign-out; signed-out transitions clear cross-account state.
10. **Settings / Downloads:** transparent playback/download rights indicators, quality preferences, sleep timer, audio settings, storage and monochrome appearance.
11. **Notifications / Help:** consistent panels, typography, focus behavior, accessible iconography and honest empty/loading/error states.
12. **Onboarding:** user preferences and territory, with non-blocking skip and device-respectful reduced motion.

## Responsive breakpoints and interaction requirements

- **Under 600 logical pixels:** five-section bottom nav plus mini-player, 2-column artwork grids, content inset from device safe areas, one-column forms and scrollable sheets.
- **600–809:** adaptive compact content, responsive grids and actionable floating player; no horizontal overflows.
- **810 and wider:** sidebar navigation, prominent content pane, floating player and responsive album rails; main content does not exceed 1440 logical pixels.
- Avoid magic screen-width math for tab hit-testing: measure the actual render box. Mini-player tap/drag must dispatch seek through player state, never merely update a decorative progress preview.
- Respect text scaling, focus order, pointer/keyboard navigation, high contrast, `MediaQuery.disableAnimationsOf` and screen reader semantics. Meaningful interactive controls use a minimum 44–48 logical pixel hit target where feasible.
- Use rounded high-contrast monochrome artwork placeholders **only when real artwork is missing**; the real catalog determines content. Avoid gradients across full UI surfaces, glowing effects, fake 3D artwork and colored accent washes.

## Native branding build contract

Generated native runners live outside source control. `tool/brand_launcher_icons_test.dart` rasterizes the supplied SVG and installs launcher icons into Android mipmap, iOS/macOS AppIcon catalogs, Windows ICO, web favicon/manifest icons and Linux package assets. All Flutter CI jobs run this step before building. A successful unit test/build does not replace app signing, store upload, Windows packaging QA, Linux desktop installation or physical-device icon acceptance.

## Figma and QA

Editable source design: https://www.figma.com/design/50wWGo2FObDEtnMY60cz60 — includes premium responsive sign-in and the source-brand-consistent Listen Now desktop and phone layouts. Additional Figma screen authoring requires more Figma MCP tool quota; that is distinct from the Flutter implementation.

PR CI checks analyzer, widget tests, Flutter Linux/Android/Web/Windows/macOS/iOS builds, database/NestJS and Cloudflare code. **Do not mark the entire consumer product 100% complete** without physical-device visual acceptance, full flows for each tab, and confirmed authorized music rights/source coverage.
