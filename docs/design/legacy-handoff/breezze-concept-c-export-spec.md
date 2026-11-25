# breezze — Concept C / The Drift
## Complete asset handoff

This package uses Concept C exclusively. No geometry from Concepts A or B is included.

### Identity geometry
- Five swept lobes arranged radially around a shared center.
- The blades are curved and directional, with negative channels between them.
- Keep the five-part rotation, center point, blade proportions, and orientation consistent.
- The mark is designed to suggest sound dispersing outward, not a flower, sun, cloud, or weather symbol.

### App icon family
- `breezze-icon-c-dark.svg` — primary dark glass treatment
- `breezze-icon-c-dark-minimal.svg` — flat dark treatment
- `breezze-icon-c-light.svg` — light mode
- `breezze-icon-c-graphite.svg` — graphite / silver
- `breezze-icon-c-blue-glass.svg` — deep blue glass
- `breezze-icon-c-tinted.svg` — currentColor transparent glyph
- `breezze-icon-c-black.svg` / `breezze-icon-c-white.svg` — monochrome glyphs
- `breezze-icon-c-notification.svg` — 24×24 notification glyph
- `breezze-icon-c-seasonal.svg` — warm orange-to-coral accent
- `breezze-icon-c-violet.svg` — cool cyan-to-violet accent

### Layered assets
- `breezze-icon-c-layer-background.svg`
- `breezze-icon-c-layer-glow.svg`
- `breezze-icon-c-layer-mark.svg`
- `breezze-icon-c-layer-highlight.svg`

Stack these in that order for animated/parallax presentations. Keep movement subtle; do not deform the mark.

### Logo and wordmark
- `breezze-logo-c.svg` — black master mark
- `breezze-logo-c-blue.svg` — blue master mark
- `breezze-logo-c-monochrome.svg` — black large mark
- `breezze-logo-c-white.svg` — white large mark
- `breezze-wordmark-c.svg` — lowercase wordmark
- `breezze-wordmark-c-white.svg` — white wordmark
- `breezze-wordmark-c-caps.svg` — uppercase fallback
- `breezze-lockup-c-horizontal.svg` — horizontal lockup
- `breezze-lockup-c-stacked.svg` — stacked lockup

### Export sizes
Export icon artwork at: 16, 32, 64, 128, 256, 512, and 1024 px.
Additional:
- Favicon: 32×32 px
- Android adaptive icon: 108dp canvas; keep all essential foreground geometry inside the central 72dp safe zone; deliver background and foreground separately.
- Android maskable: 512×512 px; keep essential content within the central 80% safe area.
- Apple Touch Icon: 180×180 px.
- Notification: 24×24 px.

### Brand tokens
- `--breezze-accent-light: #0071E3`
- `--breezze-accent-dark: #0A84FF`
- `--breezze-ground: #0A0A0C`
- `--breezze-surface: #1C1C22`
- `--breezze-glass-highlight: rgba(255,255,255,0.15)`
- `--breezze-signature-gradient: linear-gradient(135deg, #0A84FF, #5E5CE6)`

### Production notes
All SVGs are vector-only and use viewBox without fixed width/height. They include root title and description. Wordmark text uses an SF Pro Display-first font stack; for production, convert text to outlines in a design application with SF Pro Display installed. Raster PNG exports and device-specific QA should be generated from these SVG masters.

### Clear space
Maintain clear space around the mark equal to at least 50% of the mark's height on every side.

### Do
- Preserve five-lobe geometry and radial orientation.
- Use one accent hue or one restrained gradient per icon.
- Keep the mark optically centered.
- Use flat monochrome at 16px when glass details cannot reproduce cleanly.
- Keep album artwork visually dominant in the product UI.

### Don't
- Do not add literal notes, headphones, speakers, records, or play triangles.
- Do not turn the radial mark into a flower, sun, cloud, leaf, or weather icon.
- Do not add external drop shadows, heavy bevels, texture, or excessive glow.
- Do not alter the lobe count or mix in other concepts.
- Do not put text or initials inside the app icon.

### Spelling note
The exact brand spelling is `breezze` (two consecutive z characters). Preserve this spelling in all wordmarks and product references.