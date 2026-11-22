# BitChord reference review for Breezze

This document records the uploaded visual/reference materials and defines the safe implementation boundary. It does **not** import BitChord code into Breezze.

## Supplied files reviewed

- `Banner.png`: screenshot reference showing artwork-forward player, large lyric typography, dark image-led background and understated transport controls.
- `Logo.png`: BitChord's product identity — **not** a Breezze asset.
- `README.md`, `CONTRIBUTING.md`, Gradle root files and project configuration: describe a Kotlin/Jetpack Compose project and its advertised capabilities, but do not include the actual `app/`, `shared/`, `sharedUi/` or backend source implementations.

## Rights and integration boundary

The BitChord materials themselves state that BitChord is GPLv3. Reusing or distributing its implementation would require a separate GPL compatibility/compliance review, including the Corresponding Source obligations. Someone privately sharing a copy does not by itself waive the GPL or create media playback rights. Do not copy its logo, branded artwork, copyrighted lyrics, or app source verbatim into Breezze. The UPI support graphic is unrelated to product implementation and is deliberately not used.

Design patterns and generic interaction concepts are implemented independently in Flutter under Breezze's design system. Streaming permissions are independent of software licensing; no YouTube/Deezer extraction, DRM bypass, ad removal or unauthorized downloading is authorized by these reference files.

## Breezze implementation

- Reuse the existing `NowPlayingScreen` and `BzAmbientBackdrop` instead of bringing in BitChord's Kotlin UI stack.
- Keep original Breezze SVG mark, restrained dark/light tokens, dynamic artwork background, translucent transport controls and synced lyrics.
- Add an in-place **Focus lyrics / Show artwork** control: the lyrics expand into the main reading region while player controls and progress remain available.
- Preserve the existing track, playback session, seek, queue and lyric data source — switching UI modes never creates a second audio player.
- Keep artist and track labels bound to actual playback state, with loading/unavailable lyrics states.
- Limit artwork dimensions based on viewport height as well as width to reduce narrow-device overflow.
- High-contrast, animation-reduction and accessible-navigation behavior stays subject to Breezze's existing accessibility contract.

## Not ported or claimed

This does not implement or verify BitChord's lossless output, audio extraction, offline catalogue, Automix, account integration, background playback improvements or music video playback. Those require individual source/rights/implementation and end-to-end tests. The user-supplied files did not contain BitChord's source modules, and a video/branding screenshot does not demonstrate runtime behavior.

## Verification

Requires Flutter analyzer/tests and multi-platform build CI to pass. A real-device visual/interaction review is still required before calling the new player presentation visually production-ready.
