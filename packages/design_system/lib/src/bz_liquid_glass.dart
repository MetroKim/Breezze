import 'package:material_ui/material_ui.dart';

/// Liquid Glass token layer — Apple Music-conformant design system.
///
/// Spec source: "Premium Music Streaming Platform — Extended Architecture
/// & Product Sheet", Part I. Every value here is a 1:1 mapping of that
/// sheet. These tokens are additive to the existing Breezze tokens; new
/// glass surfaces consume only these.
///
/// Layer discipline (non-negotiable):
/// 1. Glass is reserved for navigation, overlays and floating controls —
///    never content cards, article panels or backgrounds.
/// 2. Maximum 2 visible blurred surfaces per viewport region.
/// 3. Bar-spawned surfaces (dropdowns, menus, popovers) are blur-free
///    near-opaque solids.
/// 4. Accent (#0071e3 / #0a84ff) is reserved for primary music actions and
///    active navigation states only — never a background wash.

// ---------------------------------------------------------------------------
// §2.1 Color system — neutral-dominant, single accent family.
// ---------------------------------------------------------------------------

/// Light palette. Cool ground (#f5f5f7), never warm cream.
class BzGlassColorsLight {
  BzGlassColorsLight._();

  /// Root page background.
  static const Color ground = Color(0xFFF5F5F7);

  /// Cards, sheets, solid panels.
  static const Color surface = Color(0xFFFFFFFF);

  /// Row hover, secondary buttons.
  static const Color surfaceHover = Color(0xFFFBFBFD);

  static const Color textPrimary = Color(0xFF1D1D1F);
  static const Color textBody = Color(0xFF424245);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color textTertiary = Color(0xFF86868B);
  static const Color textQuaternary = Color(0xFFAEAEB2);

  /// Play buttons, active nav, links, focus rings.
  static const Color accent = Color(0xFF0071E3);

  /// Accent text on tinted backgrounds.
  static const Color accentOnTint = Color(0xFF0066CC);

  /// Dividers, list separators.
  static const Color hairline = Color(0x12000000); // rgba(0,0,0,0.07)

  /// Live/online indicators (pulsing).
  static const Color live = Color(0xFF30D158);
}

/// Dark palette. Collapses to pure black for OLED efficiency.
class BzGlassColorsDark {
  BzGlassColorsDark._();

  /// Root page background — pure black.
  static const Color ground = Color(0xFF000000);

  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceHover = Color(0xFF2C2C2E);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textBody = Color(0xD9FFFFFF); // 85% white
  static const Color textSecondary = Color(0xA6FFFFFF); // 65% white
  static const Color textTertiary = Color(0x73FFFFFF); // 45% white
  static const Color textQuaternary = Color(0x4DFFFFFF); // 30% white

  static const Color accent = Color(0xFF0A84FF);
  static const Color accentOnTint = Color(0xFF409CFF);
  static const Color hairline = Color(0x1AFFFFFF); // rgba(255,255,255,0.1)
  static const Color live = Color(0xFF30D158);
}

/// Signature gradients — reserved for hero art and primary CTA only.
/// Forbidden: full-bleed gradient washes, invented hues, warm cream
/// ground, multiple accents at once.
class BzGlassGradients {
  BzGlassGradients._();

  /// Blue-to-indigo: linear-gradient(135deg, #0a84ff, #5e5ce6).
  static const List<Color> blueIndigo = [Color(0xFF0A84FF), Color(0xFF5E5CE6)];

  /// Warm-to-heat: linear-gradient(135deg, #ff9f0a, #ff375f).
  static const List<Color> warmHeat = [Color(0xFFFF9F0A), Color(0xFFFF375F)];

  /// Builds the 135deg alignment for [begin]/[end] on a [LinearGradient].
  static const Alignment begin = Alignment(-0.7, -0.7);
  static const Alignment end = Alignment(0.7, 0.7);
}

// ---------------------------------------------------------------------------
// §2.2 Liquid Glass materials — 4 named states with behavioral contracts.
// ---------------------------------------------------------------------------

/// Glass is a named material with a behavioral contract, not a generic
/// transparency value. One glass layer class per viewport region; the
/// maximum visible blurred surfaces at any time is 2.
enum BzGlassMaterial {
  /// Text-bearing top bar resting over a calm hero zone.
  ///
  /// Contract: 70–80% opacity; no busy imagery or hard contrast beneath
  /// text.
  pillAtTop,

  /// Default chrome once content can scroll beneath.
  ///
  /// Contract: 85–95% near-opaque surface + saturate(180%) blur(16px).
  /// May collapse to a blur-free near-opaque surface.
  pillScrolled,

  /// Media controls where the image remains the subject.
  ///
  /// Contract: overlay chrome only; avoid dense text.
  mediaOverlay,

  /// Sparse, large controls over rich media only.
  ///
  /// Contract: no blur backing; tint/border only; never for text-heavy
  /// nav, menus, or body copy.
  clear,
}

/// Material recipe resolution for the active [BzGlassMaterial].
class BzGlassRecipe {
  const BzGlassRecipe({
    required this.fillOpacity,
    required this.blurSigma,
    required this.saturateBoost,
  });

  /// Base fill opacity for the surface (0–1).
  final double fillOpacity;

  /// backdrop blur sigma in logical px (0 = no blur backing).
  final double blurSigma;

  /// backdrop saturate multiplier (1.0 = none; 1.8 = saturate(180%)).
  final double saturateBoost;

  /// Dark fill: rgba(28, 28, 30, opacity).
  static const Color _darkBase = Color(0xFF1C1C1E);
  static const Color _lightBase = Color(0xFFFFFFFF);

  static BzGlassRecipe of(BzGlassMaterial material) {
    switch (material) {
      case BzGlassMaterial.pillAtTop:
        return const BzGlassRecipe(
          fillOpacity: 0.75,
          blurSigma: 0,
          saturateBoost: 1.0,
        );
      case BzGlassMaterial.pillScrolled:
        // .glass-pill-scrolled:
        //   background: rgba(28,28,30,0.88);
        //   backdrop-filter: saturate(180%) blur(16px);
        return const BzGlassRecipe(
          fillOpacity: 0.88,
          blurSigma: 16,
          saturateBoost: 1.8,
        );
      case BzGlassMaterial.mediaOverlay:
        return const BzGlassRecipe(
          fillOpacity: 0.55,
          blurSigma: 12,
          saturateBoost: 1.5,
        );
      case BzGlassMaterial.clear:
        return const BzGlassRecipe(
          fillOpacity: 0.0,
          blurSigma: 0,
          saturateBoost: 1.0,
        );
    }
  }

  /// Resolved fill for [brightness] and [material].
  static Color fillOf(Brightness brightness, BzGlassMaterial material) {
    final recipe = of(material);
    final base = brightness == Brightness.dark ? _darkBase : _lightBase;
    return base.withValues(alpha: recipe.fillOpacity);
  }
}

/// Global glass budget — enforced per viewport region.
class BzGlassBudget {
  BzGlassBudget._();

  /// Maximum visible blurred surfaces at any time (NFR-007 / PRT-09).
  static const int maxVisibleBlurredSurfaces = 2;
}

// ---------------------------------------------------------------------------
// §2.3 Spacing & layout grid — 8pt system.
// ---------------------------------------------------------------------------

class BzGlassSpacing {
  BzGlassSpacing._();

  /// Inline icon-label gap.
  static const double space1 = 8;

  /// Standard margin, list row padding.
  static const double space2 = 16;

  /// Card padding, section inner padding.
  static const double space3 = 24;

  /// Section gap.
  static const double space4 = 32;

  /// Major section separator.
  static const double space5 = 48;
}

/// Semantic radius scale — not arbitrary values.
class BzGlassRadius {
  BzGlassRadius._();

  /// Tiny badges, quality chips.
  static const double sm = 4;

  /// Buttons, list rows, sidebar selection.
  static const double dfault = 8;

  /// Cards, search field.
  static const double md = 12;

  /// Floating panels, bottom sheets.
  static const double lg = 20;

  /// Large immersive overlays.
  static const double xl = 32;

  /// Search pill, player pill, tab indicators.
  static const double pill = 9999;
}

/// Minimum tap target — non-negotiable across pointer and touch (NFR-006).
class BzGlassMetrics {
  BzGlassMetrics._();

  /// Minimum 44×44 pt vertical height for every interactive element.
  static const double tapTarget = 44;

  /// Play button: 56pt visual (44pt minimum hit area).
  static const double playButtonVisual = 56;
}

// ---------------------------------------------------------------------------
// §2.4 Depth & shadow — depth-based, never decorative.
// ---------------------------------------------------------------------------

class BzGlassShadow {
  BzGlassShadow._();

  /// Floating player, side panel: 0 8px 32px rgba(0,0,0,0.12).
  static const List<BoxShadow> glassSoft = [
    BoxShadow(
      offset: Offset(0, 8),
      blurRadius: 32,
      color: Color(0x1F000000),
    ),
  ];

  /// Modal, overlay chrome: 0 12px 48px rgba(0,0,0,0.18).
  static const List<BoxShadow> glassMedium = [
    BoxShadow(
      offset: Offset(0, 12),
      blurRadius: 48,
      color: Color(0x2E000000),
    ),
  ];

  /// Top-edge specular highlight on glass:
  /// inset 0 1px 0 rgba(255,255,255,0.15) — expressed as a top hairline
  /// gradient overlay by consumers; value exposed for fidelity.
  static const Color specularHighlight = Color(0x26FFFFFF);
}

// ---------------------------------------------------------------------------
// §3 Typography — system-native stack, Dynamic Type to 300%.
// ---------------------------------------------------------------------------

/// A typography role: size, weight, tracking, line-height.
class BzGlassTypeRole {
  const BzGlassTypeRole({
    required this.fontSize,
    required this.fontWeight,
    required this.letterSpacingEm,
    required this.height,
  });

  final double fontSize;
  final FontWeight fontWeight;

  /// Tracking in em, converted to logical px at use time.
  final double letterSpacingEm;
  final double height;

  /// Resolved [TextStyle] with tracking scaled to the font size.
  TextStyle style(Color color) => TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacingEm * fontSize,
        height: height,
        color: color,
      );
}

/// The 10 named type roles. Font family stays null so the platform
/// resolves the system-native stack (SF Pro on Apple; never a web font).
class BzGlassType {
  BzGlassType._();

  /// Display / Hero — full-screen player, page hero titles.
  static const display = BzGlassTypeRole(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacingEm: -0.03,
    height: 1.14,
  );

  /// H2 / Section — carousel headers, section titles.
  static const h2 = BzGlassTypeRole(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacingEm: -0.02,
    height: 1.25,
  );

  /// H3 / Item Title — track titles, card labels.
  static const h3 = BzGlassTypeRole(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacingEm: -0.01,
    height: 1.42,
  );

  /// Long Body — descriptions, editorial copy.
  static const longBody = BzGlassTypeRole(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacingEm: 0,
    height: 1.87,
  );

  /// Summary / Lede — metadata summaries, playlist descriptions.
  static const lede = BzGlassTypeRole(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacingEm: 0,
    height: 1.6,
  );

  /// Caption — quality badges, timestamps, tertiary labels.
  static const caption = BzGlassTypeRole(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacingEm: 0,
    height: 1.33,
  );

  /// Button / Action — transport controls, primary buttons.
  static const button = BzGlassTypeRole(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacingEm: 0,
    height: 1.2,
  );
}

// ---------------------------------------------------------------------------
// §6 Motion — physics-based for glass/spatial; duration only for opacity.
// ---------------------------------------------------------------------------

/// Springs are the default for anything involving glass or spatial
/// transitions. Time-based curves are reserved for opacity and simple
/// state crossfades.
class BzGlassMotion {
  BzGlassMotion._();

  /// Hero transition: spring(response: 0.5, dampingFraction: 0.85).
  static const double heroSpringResponse = 0.5;
  static const double heroSpringDampingFraction = 0.85;

  /// Player pill appear / press feedback:
  /// stiffness ~1755, damping ~0.85 (iOS default feel).
  static const double pressStiffness = 1755;
  static const double pressDamping = 0.85;

  /// Search pill expand: spring(response: 0.4, dampingFraction: 0.85).
  static const double searchExpandSpringResponse = 0.4;
  static const double searchExpandSpringDampingFraction = 0.85;

  /// Modal crossfade (opacity only): easeInOut 200ms.
  static const Duration modalFade = Duration(milliseconds: 200);

  /// Scroll-adaptive top bar (background-color and opacity ONLY):
  /// 180–240ms. Never morph size, radius, padding or layout on a
  /// blurred bar during scroll.
  static const Duration barAdaptMin = Duration(milliseconds: 180);
  static const Duration barAdaptMax = Duration(milliseconds: 240);

  /// Immersive chrome recede: 3 seconds of no input → opacity 0.15.
  static const Duration immersiveRecedeDelay = Duration(seconds: 3);
  static const double immersiveRecedeOpacity = 0.15;
}

// ---------------------------------------------------------------------------
// §4 Layout grid & app shell.
// ---------------------------------------------------------------------------

/// Shell breakpoints per §4.2 responsive behavior.
class BzGlassBreakpoints {
  BzGlassBreakpoints._();

  /// ≥ 1200px: sidebar + main + optional side panel; floating player
  /// centered.
  static const double expanded = 1200;

  /// 810–1199px: sidebar collapses to 72px icon rail; side panel becomes
  /// overlay sheet.
  static const double medium = 810;

  /// Sidebar widths.
  static const double sidebarWidth = 260;
  static const double sidebarIconRailWidth = 72;

  /// Optional fixed right-hand panel ("Up Next" / "Lyrics").
  static const double sidePanelWidth = 300;

  /// Floating player pill anchor: bottom 20px, centered.
  static const double playerPillBottomInset = 20;

  /// Compact shell: player pill docks with 16px horizontal margins.
  static const double playerPillCompactHorizontalMargin = 16;
}
