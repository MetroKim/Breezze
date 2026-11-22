# Breezze Design System — Apple Music "Liquid Glass" Edition

The interface matches Apple Music 100%: **content is the interface; chrome
is a functional layer that floats above it.** Glass is a named material
reserved for navigation and control. It is never used on content cards,
article panels, or backgrounds.

## Layer discipline (non-negotiable)

- **Unified surface > fragmented cards.** Group sibling content on one
  solid panel with hairline dividers, not multiple rounded cards.
- **Glass is seasoning.** `BackdropFilter` only where layers overlap:
  nav, overlays, floating controls.
- **Restraint is luxury.** Solve layout with whitespace and hierarchy
  before adding borders, fills, or icons.
- **Hierarchy from weight + size + grayscale.** Color is an accent for
  action and state — never a background wash.
- **One glass layer class per viewport region.** The maximum visible
  blurred surfaces at any time is **2**. Bar-spawned surfaces
  (dropdowns, menus, popovers) are unconditionally near-opaque,
  blur-free solids.

## Color (§2.1) — `BzColorsLight` / `BzColorsDark`

| Token | Light | Dark |
|---|---|---|
| ground | `#f5f5f7` (cool, never cream) | `#000000` (OLED black) |
| surface | `#ffffff` | `#1c1c1e` |
| surface-hover | `#fbfbfd` | `#2c2c2e` |
| text-primary | `#1d1d1f` | `#ffffff` |
| text-secondary | `#6e6e73` | white 65% |
| text-tertiary | `#86868b` | white 45% |
| text-quaternary | `#aeaeb2` | white 30% |
| accent | `#0071e3` | `#0a84ff` |
| accent-on-tint | `#0066cc` | `#409cff` |
| hairline | 7% black | 10% white |
| live | `#30d158` | `#30d158` |

Accent is reserved **exclusively** for primary music actions and active
navigation states. Signature gradients (`BzGradients.hero` blue→indigo,
`BzGradients.warm` warm→heat) are reserved for hero art and primary CTA
only. Forbidden: full-bleed gradient washes, invented hues, warm cream
ground, multiple accents at once.

## Glass material states (§2.2)

Glass is a named material with a behavioral contract:

| State | Legal use | Contract |
|---|---|---|
| pill-at-top | Text-bearing top bar over a calm hero zone | 70–80% opacity; no busy imagery beneath text |
| pill-scrolled | Default chrome once content can scroll beneath | 85–95% near-opaque + blur(12–16px) + saturate(180%) |
| media-overlay | Media controls where the image remains the subject | 55% fill, overlay chrome only; avoid dense text |
| clear | Sparse, large controls over rich media only | No blur backing; tint/border only |

Recipe (`pill-scrolled`, dark): fill `#1c1c1e` at 88%,
blur 16px with a 180% saturation boost, hairline border, specular top
edge. Without the saturation boost the material reads as generic
translucency — it is not optional.

Fills: `atmoRegular` = pill-scrolled, `atmoClear` = media-overlay,
`softDiffuse` = ambient tint. Opaque fallback when reduced transparency
or high contrast is on.

## Spacing & radius (§2.3) — `BzSpacing` / `BzRadius`

8pt grid. `space1..space5` = 8/16/24/32/48. Radius: `sm` 4, `standard`
8, `md` 12, `lg` 20, `xl` 32, `pill` 999. Tap targets: **44×44pt
minimum, non-negotiable.**

## Depth (§2.4) — `BzShadow`

Depth-based, never decorative. `glassSoft` 0/8/32 @12%,
`glassMedium` 0/12/48 @18%, plus the specular top-edge highlight.

## Typography (§3) — `BzType` / `BzTypography`

System-native stack only (SF Pro on Apple; never Inter/Roboto web
fonts). Fluid roles with tracking (`BzTypography.display` … `.action`).
Every text style scales with the user's system font settings; the UI
must remain usable at 300% font size.

## Motion (§6) — `BzSprings` / `BzMotion`

Physics-based for anything glass or spatial: press/pill spring
stiffness 1755, ratio 0.85; hero/glass-morph response 0.5, ratio 0.85.
Time-based durations (`modalFadeMs` 200, bar adapt 180–240ms) are
reserved for opacity and simple crossfades only.

**Critical constraint:** never morph size, radius, padding, or layout on
a blurred bar during scroll. Animate only background-color and opacity.

## Shell geometry (§4.1/§4.2) — `BzBreakpoints`

- ≥1200px: 260px glass sidebar + main + optional 300px side panel;
  floating player pill centered, bottom 20px.
- 810–1199px: sidebar collapses to 72px icon rail; side panel becomes
  overlay sheet.
- <810px: sidebar becomes bottom tab bar (glass); player pill docks to
  the bottom safe area with 16px horizontal margins.
- Immersive mode: chrome recedes to opacity 0.15 after 3s of no input;
  any touch restores instantly.

## Figma handoff

This document is the token + material source of truth. Create Figma
variables 1:1 from `BzColorsLight/Dark`, `BzTypography`, `BzRadius`,
`BzSpacing`, `BzSprings`, `BzShadow`, `BzBreakpoints`.
