# Breezze design reference repositories

This is a curated implementation reference list for the existing Breezze Flutter application. These projects are references, not upstream dependencies. Do not copy whole applications, replace Breezze architecture, or import provider-specific playback/source code.

## Selected references

### 1. Aura Music Player — mature player interaction and accessibility
- Repository: https://github.com/Mehrschad/aura_music_player
- License: MIT (verify the repository LICENSE before copying any source file).
- Useful patterns: AMOLED-first visual hierarchy, typography-led player, waveform seek bar, synced and word-timed lyrics, smart playlists, explicit accessibility and reduced-motion support.
- Breezze adaptation: study player hierarchy, lyrics focus states, seek interaction and accessibility behavior. Keep Breezze's backend-authorized playback resolver and existing audio contracts.

### 2. Troona Music — artwork-led atmosphere and Flutter composition
- Repository: https://github.com/donfreddy/troona-music
- License: MIT.
- Useful patterns: artwork-derived palette, restrained glass materials, hero artwork transitions, feature-first Clean Architecture, and documented BackdropFilter performance limits.
- Breezze adaptation: use artwork as a subtle contextual surface, not as a permanent full-screen blur. Keep blur layers sparse, isolate expensive artwork rendering, and preserve Breezze semantic theme tokens.

### 3. Wavelength — navigation and offline-first Flutter structure
- Repository: https://github.com/Sanjay7127/wavelength
- License: MIT (repository states it is derivative work; read ATTRIBUTION.md and LICENSE before reusing code).
- Useful patterns: Riverpod feature-first organization, go_router StatefulShellRoute, persistent tab state, library/history/favorites organization, and clear architecture documentation.
- Breezze adaptation: compare shell/navigation behavior and library structure. Do not import its local-file-only assumptions into Breezze's streaming model.

### 5. Lucide Icons Flutter — consistent icon language
- Package: https://pub.dev/packages/lucide_icons_flutter
- License: MIT.
- Useful patterns: consistent outline icon family, predictable stroke weights, broad coverage for navigation, playback, library and item actions.
- Breezze adaptation: introduce a small `BzIcon` wrapper and standardize size/stroke/color through Breezze tokens. Prefer authored SVG assets where an exact brand-specific vector is required; do not mix several unrelated icon families.

### 4. shad — reusable Flutter component API and theme discipline
- Package: https://pub.dev/packages/shad
- Source: https://github.com/Serverpod/shadcn_flutter
- License: MIT.
- Useful patterns: cohesive component APIs, accessible forms/menus/sheets, consistent radii and typography, theme composition, and light/dark parity.
- Breezze adaptation: use as a component-design reference. Do not replace `breezze_design_system` or introduce a second competing theme system.

## Deliberately not adopted

- Xono (https://github.com/vikhil-x/xono): its README describes it as educational and its repository page did not expose a license during this review. Do not copy code without a confirmed license.
- Older Dribbble/demo music-player repositories: many are useful for screenshots but use dated dependencies, incomplete playback lifecycles, or weak architecture. Borrow visual ideas only after checking current code and license.
- Provider scraping, stream extraction, or download pipelines from unrelated music clients: not relevant to Breezze's rights-checked playback contract and must not be transplanted.

## Integration rules

1. Prefer adapting a small, isolated widget or interaction over adding a whole UI framework.
2. Preserve Breezze's existing `BzThemeColors`, `BzSpacing`, `BzRadius`, `BzMotion`, and `BzType` tokens as the single visual source of truth.
3. Keep all screen content backed by real API/local data. Do not add fake charts, editorial playlists, artist portraits, station playback, or download-completion states.
4. Keep audio operations in the player controller/audio contracts, not in presentation widgets.
5. Use semantic labels, minimum 44–48 logical-pixel touch targets, keyboard/focus support where applicable, text scaling, and reduced-motion-aware animation.
6. Any copied/adapted source must retain its required copyright/license notice and be recorded in an attribution file.
7. Do not add dependencies solely for a screenshot-level effect. Every dependency must justify bundle size, maintenance, accessibility and test cost.

## Design target

Breezze should feel like a mature, content-first music product: restrained monochrome foundation, album artwork as the primary color, strong typography, consistent spacing, fast navigation, accessible controls, and motion that communicates state. Avoid neon gradients, decorative glass everywhere, fake futuristic effects, emoji icons, and generic dashboard cards.
