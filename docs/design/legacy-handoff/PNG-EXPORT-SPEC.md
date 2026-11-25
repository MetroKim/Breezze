# breezze — SVG handoff & PNG export specification

## Included files
- `breezze-logo-a.svg` — Airflow concept
- `breezze-logo-b.svg` — Glass Disc concept (recommended)
- `breezze-logo-c.svg` — Drift concept
- `breezze-icon-dark.svg` — default dark app icon
- `breezze-icon-light.svg` — light icon
- `breezze-icon-tinted.svg` — monochrome/tinted glyph
- `breezze-icon-notification.svg` — 24×24 notification glyph
- `breezze-icon-layer-background.svg`, `breezze-icon-layer-glow.svg`, `breezze-icon-layer-mark.svg` — separate motion layers
- `breezze-icon-seasonal.svg` — warm accent variation
- `breezze-mark.svg`, `breezze-mark-monochrome.svg` — standalone marks
- `breezze-wordmark.svg`, `breezze-wordmark-caps.svg`
- `breezze-lockup-horizontal.svg`, `breezze-lockup-stacked.svg`

## Raster export matrix
Export the square icon artwork at each of these exact pixel dimensions:
16, 32, 64, 128, 256, 512, 1024 px.
Additional exports:
- Favicon: 32×32 px (`breezze-icon-dark.svg`)
- Android adaptive foreground: 108dp canvas with mark contained inside the central 72dp safe zone; supply background as a separate solid layer.
- Android maskable raster: 512×512 px; keep all essential mark geometry within the central 80% safe area.
- Apple Touch Icon: 180×180 px (`breezze-icon-dark.svg`).

## Rendering notes
- All SVGs use `viewBox` and omit fixed width/height attributes.
- SVGs are vector-only. No embedded raster images or external dependencies.
- Use SVG as the master. Rasterize with a standards-compliant renderer at target dimensions.
- At 16px, use the monochrome mark where possible; avoid relying on the highlight strokes.
- Wordmark uses an SF Pro Display-first font stack. For deterministic outlined typography, open in a design tool with SF Pro Display installed and convert the text to outlines before final production.

## Brand tokens
- `--breezze-accent-light: #0071E3`
- `--breezze-accent-dark: #0A84FF`
- `--breezze-ground: #0A0A0C`
- `--breezze-surface: #1C1C22`
- `--breezze-glass-highlight: rgba(255,255,255,0.15)`
- `--breezze-signature-gradient: linear-gradient(135deg, #0A84FF, #5E5CE6)`

## Concept B decision
The Glass Disc is the strongest system anchor: its outer circular mass survives reduction, while the asymmetric aperture gives it a proprietary silhouette. Keep the aperture geometry unchanged across app icon, favicon, notification, and lockup contexts.