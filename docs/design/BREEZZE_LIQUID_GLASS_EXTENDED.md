# Breezze Liquid Glass — Extended Design & Engineering Architecture

Status: **Phase 0 (foundations) in progress.** This document binds the extended
"Liquid Glass" product sheet to the existing `breezze_design_system` package.
It extends — does not replace — `docs/design/BREEZZE_INTERFACE_CONTRACT.md`.

## 1. Design philosophy & layer discipline

One principle: **content is the interface; chrome is a functional layer that
floats above it.** Glass is not decoration — it is a material reserved for
navigation and control. It must never appear on content cards, article panels,
or backgrounds.

- **Unified surface > fragmented cards** — group sibling content on one solid
  panel with hairline dividers, not multiple rounded cards.
- **Glass is seasoning** — backdrop blur only where layers overlap: nav,
  overlays, floating controls, colored CTAs.
- **Restraint is luxury** — solve layout with whitespace and hierarchy before
  adding borders, fills, or icons.
- **Hierarchy from weight + size + grayscale** — color is an accent for action
  and state, never a background wash.
- **One glass layer class per viewport region** — stacking two glass surfaces
  makes the lower one meaningless; merge, solidify, or demote one.

Engineering consequence (NFR-007, PRT-09): **maximum 2 visible blurred
surfaces at any time.** Bar-spawned surfaces (dropdowns, menus, popovers,
sheets) are unconditionally near-opaque blur-free solids — they never inherit
the glass material of their parent bar.

## 2. Design tokens

### 2.1 Color system

Neutral-dominant palette with a single accent family. Light mode uses a cool
ground (`#f5f5f7`), never warm cream. Dark mode collapses to pure black
(`#000000`) for OLED efficiency.

| Token | Light | Dark | Usage |
|---|---|---|---|
| `ground` | `#f5f5f7` | `#000000` | Root page background |
| `surface` | `#ffffff` | `#1c1c1e` | Cards, sheets, solid panels |
| `surfaceHover` | `#fbfbfd` | `#2c2c2e` | Row hover, secondary buttons |
| `textPrimary` | `#1d1d1f` | `#ffffff` | Titles, primary labels |
| `textBody` | `#424245` | `rgba(255,255,255,0.85)` | Long body copy |
| `textSecondary` | `#6e6e73` | `rgba(255,255,255,0.65)` | Metadata, timestamps |
| `textTertiary` | `#86868b` | `rgba(255,255,255,0.45)` | Captions, quality badges |
| `textQuaternary` | `#aeaeb2` | `rgba(255,255,255,0.30)` | Placeholders, faint numbers |
| `accent` | `#0071e3` | `#0a84ff` | Play buttons, active nav, links, focus rings |
| `accentOnTint` | `#0066cc` | `#409cff` | Accent text on tinted backgrounds |
| `hairline` | `rgba(0,0,0,0.07)` | `rgba(255,255,255,0.10)` | Dividers, list separators |
| `live` | `#30d158` | `#30d158` | Live/online indicators (pulsing) |

Signature gradients (hero art and primary CTA only):
- `linear-gradient(135deg, #0a84ff, #5e5ce6)` — blue-to-indigo
- `linear-gradient(135deg, #ff9f0a, #ff375f)` — warm-to-heat

Forbidden: full-bleed gradient washes, invented hues, warm cream ground,
multiple accents at once.

### 2.2 Liquid Glass materials — 4 states

Glass is a named material with a behavioral contract, not a generic
transparency value.

| State | Legal use | Material contract |
|---|---|---|
| `pillAtTop` | Text-bearing top bar resting over a calm hero zone | 70–80% opacity tint; no busy imagery or hard contrast beneath text |
| `pillScrolled` | Default chrome once content can scroll beneath | 85–95% near-opaque surface + `blur(12–16px)` + `saturate(180%)`; may collapse to blur-free near-opaque |
| `mediaOverlay` | Media controls where the image remains the subject | Old atmosphere recipe demoted to overlay chrome only; avoid dense text |
| `clear` | Sparse, large controls over rich media only | No blur backing; tint/border only; never for text-heavy nav, menus, or body |

The `saturate(180%)` boost and `blur(16px)` on `pillScrolled` are
non-negotiable; without them the material reads as generic translucency.

### 2.3 Spacing & radii

8pt grid. Radii follow a semantic scale: `4` (badges/chips), `8`
(buttons/list rows), `12` (cards/search field), `20` (floating panels/sheets),
`32` (large immersive overlays), `9999` (pills).

Tap targets: minimum 44×44 pt vertical height for every interactive element,
across pointer and touch. Non-negotiable.

### 2.4 Depth & shadow

- `shadowGlassSoft` — `0 8px 32px rgba(0,0,0,0.12)` — floating player, side panel
- `shadowGlassMedium` — `0 12px 48px rgba(0,0,0,0.18)` — modal, overlay chrome
- `shadowSpecular` — top-edge highlight `rgba(255,255,255,0.15)`, inset

Never hard drop shadows on glass.

## 3. Typography

System-native stack only — never a web font. Apple platforms resolve to San
Francisco; web falls back to `-apple-system, BlinkMacSystemFont, 'SF Pro Text',
'SF Pro Display', 'Helvetica Neue'`.

Dynamic Type: every text style scales with the user's system font settings;
the UI must remain usable at 300% font size. Use relative units for spacing
tied to text.

## 4. Shell layout

- **≥1200px** — 260px glass sidebar (`pillScrolled`) + main scroll + optional
  300px glass side panel (Up Next / Lyrics); floating glass player pill
  centered `bottom: 20px`.
- **810–1199px** — sidebar collapses to 72px icon rail; side panel becomes an
  overlay sheet.
- **<810px** — glass bottom tab bar; main content full-width; player pill docks
  to the bottom safe area with 16px horizontal margins.
- **Immersive mode** — all chrome recedes to `opacity: 0.15` after 3 seconds
  without input; any touch restores instantly.

The floating glass player pill and the sidebar glass material are the two
signals that separate a premium interface from a flat streaming list.

## 5. Motion

Physics-based (springs) for glass and spatial transitions; time-based curves
only for opacity and state crossfades.

- Player pill / press — spring, stiffness 1755, damping ratio 0.85
- Hero transition — spring response 0.5, damping fraction 0.85
- Scroll-adaptive bar — animate background-color and opacity only, 180–240ms;
  never morph size, radius, padding, or layout on a blurred bar during scroll.

## 6. Attribution & third-party policy

The techniques in this document — the shared-backdrop sampling architecture,
resolution-scaled blur, layered quality tiers, luminance-driven content color,
accessibility collapse-to-solid — were studied from:

- **BitChord** (github.com/kushagrasinghx/BitChord) — GPL-3.0.
- **EchoMusicApp/Echo-Music** — GPL-3.0 (BitChord's own upstream).

**No GPL-licensed source code is copied into this repository.** Only
non-copyrightable engineering techniques and publicly-measured design
constants are adopted. All Breezze implementation code is original Dart,
per `docs/legal/BREEZZE_THIRD_PARTY_CODE_POLICY.md`.

## 7. Phase plan (PRT-bound)

| Phase | Deliverable | PRT |
|---|---|---|
| 0 | Token migration + `BzGlass` state library + blur-budget host + a11y fallback + tests | PRT-09, NFR-006/007 |
| 1 | Shell: 260px glass sidebar, floating player pill, icon rail, bottom tab bar, immersive recede | PRT-05, PRT-10 |
| 2 | Search pill, waveform scrubber, quality badge sheet, artwork cards, download toggle | PRT-01/02/04/07 |
| 3 | Spring motion layer, press illumination, scroll-adaptive bar | PRT-10 |
| 4 | Blur-count perf metric, lint enforcement, 300% type pass, reduce-motion pass | PRT-08/09 |
