# Breezze Design System — Premium Glass Edition

Design language inspired by Liner's principles (content is the colour,
glass not boxes, calm motion) — adapted into Breezze's own monochrome
identity. No Liner assets, code, fonts, or trade dress copied.

## Core principles (adapted, our own execution)

1. **Content is the interface.** Glass is a material reserved for
   navigation and control. It is never used on content cards, article
   panels, or backgrounds. Maximum 2 visible blurred surfaces per
   viewport.
2. **Glass is seasoning.** Translucent tint + blur only where layers
   overlap: nav, overlays, floating controls. Bar-spawned surfaces
   (dropdowns, menus, popovers) are unconditionally near-opaque,
   blur-free solids.
3. **Restraint is luxury.** Solve layout with whitespace and hierarchy
   before adding borders, fills, or icons. Hierarchy comes from weight,
   size, and grayscale; the blue accent is for action and state only —
   never a background wash.
4. **Calm motion.** One easing curve `Cubic(0.22, 1, 0.36, 1)`. Fades
   100–200ms. Springs only for things that "land" (stiffness ~1755,
   damping ~0.85). Scroll-adaptive bars animate background-color and
   opacity ONLY — never size, radius, padding, or layout.
5. **Artwork forward.** Square cards, 12px radius, no glass on the card
   itself. Hover: gentle scale 1.02, no shadow bloom.

## Glass material states

| State | Legal use | Material contract |
|---|---|---|
| pill-at-top | Text-bearing top bar over a calm hero zone | 70–80% opacity, no busy imagery beneath text |
| pill-scrolled | Default chrome once content scrolls beneath | 85–95% near-opaque + `saturate(180%) blur(16px)`; may collapse to blur-free near-opaque |
| media-overlay | Media controls where the image stays the subject | 55% fill; avoid dense text |
| clear | Sparse, large controls over rich media only | No blur backing; tint/border only; never for text-heavy UI |

Opaque fallback when reduced transparency or high-contrast is on.

## Motion tokens

```dart
class BzMotion {
  static const int instantMs = 100;
  static const int fastMs = 160;
  static const int navMs = 240;
  static const int artworkMs = 360;
  static const int expandMs = 420;
  static const int sheetMs = 320;
  static const int morphMs = 450;
  static const int breathMs = 2000; // idle loop, ease in-out
  static const int barAdaptMs = 200; // background-color/opacity only
}
```

## Glass recipe (dark theme reference)

- Mini-player capsule: fill `atmoRegular` (88% surface-1), blur 24px,
  hairline `separator` border, radius 999 (capsule).
- Tab bar: same fill, blur 16px, active pill `text1`, inactive `text2`.
- Sheets: `atmoClear` fill, blur 32px, radius 20.
- Dialogs and menus: `surfaceElevated` / `surfacePrimary` solid
  (never glass) — bar-spawned surfaces never inherit parent glass.

## Where each material is used

| Surface | Material | Blur |
|---|---|---|
| Mini-player capsule | atmoRegular | 24 |
| Tab bar capsule | atmoRegular | 16 |
| Now Playing backdrop | artwork-derived ambient | 60 |
| Sheets / queue | atmoClear | 32 |
| Settings rows / content cards | surface1 solid | 0 |
| Dialogs, menus, popovers | solid, blur-free | 0 |

## Accent discipline

`accent` (#0071e3 light / #0a84ff dark) is reserved exclusively for
primary music actions (play buttons, transport) and active navigation
states. It must never appear as a background or decorative wash.
Signature gradients — `135deg #0a84ff→#5e5ce6` and `135deg #ff9f0a→#ff375f` —
are reserved for hero art and the primary CTA only.

## Figma handoff

This document is the token + material source of truth. Figma variables
should be created 1:1 from BzColorsLight/Dark, BzType, BzRadius,
BzSpacing, BzMotion. Components: BzTabBar, BzMiniPlayer,
BzGlassContainer, BzArtworkCard, BzLyricLine, BzSongRow.
