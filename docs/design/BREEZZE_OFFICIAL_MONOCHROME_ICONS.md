# Breezze official monochrome icon system

Status: **pre-release design source**. Do not publish a release, change existing platform launcher icons, or deploy production from this handoff. Visual acceptance is still required.

## Authority

The source is `apps/mobile/assets/icons/breezze-app-icon.svg`, the existing official pixel-B glyph used by Breezze. The SVG path geometry, placement (`translate(305,174) scale(1.87)`) and rounded square (`rx=218`) are preserved byte-for-byte, with only the foreground/background color changed. **No externally generated logo or replacement shape** is used.

## Four intentional uses

| Asset | Usage |
| --- | --- |
| `breezze-app-monochrome-dark.svg` | True #000000 tile with #FFFFFF official mark; dark UI and white-on-black brand collateral |
| `breezze-app-monochrome-light.svg` | True #FFFFFF tile with #000000 official mark; light UI and black-on-white collateral |
| `breezze-symbol-monochrome-adaptive.svg` | Transparent official pixel-B mark with currentColor; tinted by semantic theme color in Flutter |
| Existing `breezze-logo-white.svg` and `breezze-logo-black.svg` | Preserve existing original wordmark lockups unchanged, including their historical SVG and PNG counterparts |

The legacy official tile and all original assets are retained. The alternative glossy B-note and ribbon explorations remain archived; they are not substituted for the approved pixel-B brand.

## Flutter integration

`BzMonochromeAppIcon` selects the two app-tile variants from theme brightness, used on sign-in and the desktop navigation brand. `BzBnoteMark` now consumes a single adaptive SVG source and applies the semantic color at rendering time. All navigation glyphs remain one-color `currentColor` SVGs, and Browse uses its existing compass icon rather than the previous 'New' icon.

## Verification / release block

Tests compare the entire official path-data sequence between the source and each monochrome variant, plus verify light/dark widget mounting. This is **source-level geometry verification**, not subjective design approval. Still needed: high-DPI screenshot review, full small-screen testing, accessibility review with VoiceOver/TalkBack, launcher icon treatment sign-off, and full-app completion before any production release.
