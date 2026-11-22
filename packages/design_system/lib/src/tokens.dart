import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Breezze design tokens — Apple Music "Liquid Glass" contract (§2).
///
/// Semantic tokens only. No literal colors are allowed anywhere else in
/// the app; every surface, text, and control consumes these.
///
/// Palette contract (§2.1):
/// - Neutral-dominant with a single accent family (#0071e3 / #0a84ff).
/// - Light ground is cool #f5f5f7 — never warm cream.
/// - Dark ground collapses to pure black for OLED efficiency.
/// - Accent is reserved for primary music actions and active navigation
///   states. It is never a background or decorative wash.
class BzColorsLight {
  // Ground / surfaces.
  static const background = Color(0xFFF5F5F7); // --color-ground
  static const surfacePrimary = Color(0xFFFFFFFF); // --color-surface
  static const surfaceSecondary = Color(0xFFFBFBFD); // --color-surface-hover
  static const surfaceElevated = Color(0xFFFFFFFF);

  // Text hierarchy.
  static const textPrimary = Color(0xFF1D1D1F);
  static const textSecondary = Color(0xFF6E6E73);
  static const textTertiary = Color(0xFF86868B);
  static const textQuaternary = Color(0xFFAEAEB2);

  // Lines & state.
  static const separator = Color(0x12000000); // --color-hairline (7% black)
  static const brandMonochrome = Color(0xFF1D1D1F);
  static const accent = Color(0xFF0071E3);
  static const accentOnTint = Color(0xFF0066CC);
  static const success = Color(0xFF30D158); // --color-live
  static const warning = Color(0xFFFF9F0A);
  static const error = Color(0xFFFF3B30);
}

class BzColorsDark {
  static const background = Color(0xFF000000); // OLED pure black
  static const surfacePrimary = Color(0xFF1C1C1E); // --color-surface
  static const surfaceSecondary = Color(0xFF2C2C2E); // --color-surface-hover
  static const surfaceElevated = Color(0xFF2C2C2E);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xA6FFFFFF); // 65%
  static const textTertiary = Color(0x73FFFFFF); // 45%
  static const textQuaternary = Color(0x4DFFFFFF); // 30%

  static const separator = Color(0x1AFFFFFF); // --color-hairline (10% white)
  static const brandOnDark = Color(0xFFFFFFFF);
  static const accent = Color(0xFF0A84FF);
  static const accentOnTint = Color(0xFF409CFF);
  static const success = Color(0xFF30D158);
  static const warning = Color(0xFFFF9F0A);
  static const error = Color(0xFFFF453A);

  // Atmosphere material overlays (legacy names, Liquid Glass values).
  static const atmoRegular = Color(0xE01C1C1E); // pill-scrolled fill, 88%
  static const atmoClear = Color(0x8C1C1C1E); // media-overlay fill, 55%
  static const softDiffuse = Color(0x80000000); // ambient diffuse, 50%
}

class BzColorsLightAtmo {
  static const atmoRegular = Color(0xE0F5F5F7); // 88%
  static const atmoClear = Color(0x8CFFFFFF); // 55%
  static const softDiffuse = Color(0x80F5F5F7); // 50%
}

/// Signature gradients (§2.1) — reserved for hero art and primary CTA
/// only. Forbidden: full-bleed gradient washes and invented hues.
class BzGradients {
  /// Blue-to-indigo, 135deg: #0a84ff → #5e5ce6.
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
  );

  /// Warm-to-heat, 135deg: #ff9f0a → #ff375f.
  static const LinearGradient warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9F0A), Color(0xFFFF375F)],
  );
}

/// Spacing — 8pt grid (§2.3). All spacing, padding, and component gaps are
/// increments of 8 (4 is the only micro-exception for optical alignment).
class BzSpacing {
  // Legacy scale (existing call sites).
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  // Spec scale.
  static const double space1 = 8; // --space-1: inline icon-label gap
  static const double space2 = 16; // --space-2: standard margin, row padding
  static const double space3 = 24; // --space-3: card / section inner padding
  static const double space4 = 32; // --space-4: section gap
  static const double space5 = 48; // --space-5: major section separator

  /// Minimum interactive target, 44x44pt — non-negotiable (§2.3, NFR-006).
  static const double tapTarget = 44;
}

/// Radius — semantic scale (§2.3), never arbitrary values.
class BzRadius {
  static const double sm = 4; // --radius-sm: badges, quality chips
  static const double standard = 8; // --radius-default: buttons, list rows
  static const double button = 8;
  static const double md = 12; // --radius-md: cards, search field
  static const double input = 12;
  static const double artwork = 12;
  static const double card = 12;
  static const double lg = 20; // --radius-lg: floating panels, sheets
  static const double sheet = 20;
  static const double xl = 32; // --radius-xl: large immersive overlays
  static const double modal = 32;
  static const double capsule = 999;
  static const double pill = 999; // --radius-pill: search, player, tabs
}

/// Elevation levels (legacy numeric ladder; prefer [BzShadow]).
class BzElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 2;
  static const double level3 = 3;
  static const double level4 = 4;
  static const double level5 = 5;
}

/// Depth & shadow (§2.4). Shadows are depth-based, not decorative: a glass
/// surface lifts with a low-opacity, large-radius shadow plus a specular
/// highlight on its top edge — never a hard drop shadow.
class BzShadow {
  /// --shadow-glass-soft: floating player pill, side panel.
  static const BoxShadow glassSoft = BoxShadow(
    color: Color(0x1F000000), // 12% black
    offset: Offset(0, 8),
    blurRadius: 32,
  );

  /// --shadow-glass-medium: modal, overlay chrome.
  static const BoxShadow glassMedium = BoxShadow(
    color: Color(0x2E000000), // 18% black
    offset: Offset(0, 12),
    blurRadius: 48,
  );

  /// --shadow-specular: top-edge highlight on glass (15% white). Applied as
  /// a 1px inner top border by the glass widgets, not as a BoxShadow.
  static const Color specular = Color(0x26FFFFFF);
}

/// Motion (§6). Physics-based for anything involving glass or spatial
/// transitions; time-based durations are reserved for opacity and simple
/// state crossfades only.
class BzMotion {
  // Legacy durations — opacity/state crossfades only. Never use these to
  // morph size, radius, padding, or layout on a blurred bar.
  static const int instantMs = 100;
  static const int fastMs = 160;
  static const int navMs = 240;
  static const int artworkMs = 360;
  static const int expandMs = 420;
  static const int sheetMs = 320;
  static const int morphMs = 450;
  static const int breathMs = 2000;

  // Spec motion tokens.
  static const int modalFadeMs = 200; // --motion-modal-fade (easeInOut)
  static const int barAdaptMinMs = 180; // --motion-bar-adapt range
  static const int barAdaptMaxMs = 240;
}

/// A spring described by stiffness and damping (unit mass).
class BzSpringSpec {
  final double stiffness;
  final double damping;

  const BzSpringSpec({required this.stiffness, required this.damping});

  /// Damping ratio; 1.0 is critically damped.
  double get dampingRatio => damping / (2 * math.sqrt(stiffness));
}

/// Spring motion tokens (§6). Press feedback and pill landings share the
/// stiff 1755 spring; hero and glass morphs share the softer 0.5-response
/// spring. All at damping fraction 0.85.
class BzSprings {
  /// --motion-press / --motion-pill-spring: stiffness 1755, ratio 0.85.
  static const BzSpringSpec press = BzSpringSpec(stiffness: 1755, damping: 71.2);
  static const BzSpringSpec pill = BzSpringSpec(stiffness: 1755, damping: 71.2);

  /// --motion-hero-spring / --motion-glass-morph: response 0.5, fraction 0.85.
  static const BzSpringSpec hero = BzSpringSpec(stiffness: 157.9, damping: 21.4);
  static const BzSpringSpec glassMorph = BzSpringSpec(stiffness: 157.9, damping: 21.4);
}

/// Type scale (§3) — native platform sizes (Apple HIG ladder). System
/// fonts only; never a bundled web font.
class BzType {
  static const double display = 40;
  static const double largeTitle = 34;
  static const double title1 = 28;
  static const double title2 = 22;
  static const double title3 = 18;
  static const double headline = 17;
  static const double body = 16;
  static const double subheadline = 14;
  static const double footnote = 12;
  static const double caption = 11;
}

/// Fluid typography roles (§3) with spec tracking and line height. Sizes
/// clamp to the spec ranges; call sites resolve the fluid size from the
/// viewport width and must also respect the user's system text scale.
class BzTypography {
  static double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  /// Fluid size resolvers (viewport width in logical px).
  static double displaySize(double vw) => _clamp(vw * 0.05, 27, 46);
  static double h2Size(double vw) => _clamp(vw * 0.034, 20, 26);
  static double h3Size(double vw) => _clamp(vw, 15.5, 18);
  static double longBodySize(double vw) => _clamp(vw * 0.026, 16, 18);
  static double summarySize(double vw) => _clamp(vw, 15, 19);

  /// Display / Hero — full-screen player and page hero titles.
  static TextStyle display(double fontSize) {
    final s = _clamp(fontSize, 27, 46);
    return TextStyle(
      fontSize: s,
      fontWeight: FontWeight.w700,
      letterSpacing: s * -0.03,
      height: 1.14,
    );
  }

  /// H2 / Section — carousel headers, section titles.
  static TextStyle h2(double fontSize) {
    final s = _clamp(fontSize, 20, 26);
    return TextStyle(
      fontSize: s,
      fontWeight: FontWeight.w700,
      letterSpacing: s * -0.02,
      height: 1.25,
    );
  }

  /// H3 / Item title — track titles, card labels.
  static TextStyle h3(double fontSize) {
    final s = _clamp(fontSize, 15.5, 18);
    return TextStyle(
      fontSize: s,
      fontWeight: FontWeight.w600,
      letterSpacing: s * -0.01,
      height: 1.42,
    );
  }

  /// Long body — descriptions, editorial copy.
  static TextStyle longBody(double fontSize) {
    final s = _clamp(fontSize, 16, 18);
    return TextStyle(fontSize: s, fontWeight: FontWeight.w400, height: 1.87);
  }

  /// Summary / lede — metadata summaries, playlist descriptions.
  static TextStyle summary(double fontSize) {
    final s = _clamp(fontSize, 15, 19);
    return TextStyle(fontSize: s, fontWeight: FontWeight.w400, height: 1.6);
  }

  /// Caption — quality badges, timestamps, tertiary labels.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
  );

  /// Button / action — transport controls, primary buttons.
  static const TextStyle action = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

/// Shared responsive breakpoints for the adaptive Flutter shell (§4.2).
class BzBreakpoints {
  static const double compact = 600;
  static const double medium = 810; // below: bottom tab bar shell
  static const double iconRailMin = 810; // 810–1199: 72px icon rail
  static const double expanded = 1200; // 1200+: full sidebar + side panel
  static const double sidebarMin = 1200;
  static const double wide = 1600;
  static const double contentMaxWidth = 1440;

  // Shell geometry (§4.1).
  static const double sidebarWidth = 260;
  static const double iconRailWidth = 72;
  static const double sidePanelWidth = 300;
  static const double playerPillBottomInset = 20;
  static const double playerPillHorizontalMargin = 16; // < 810px docking

  /// Bottom clearance reserved for the persistent mini-player/navigation.
  /// Desktop places playback in the floating pill, so content needs less
  /// room.
  static double bottomClearance(
    BuildContext context, {
    double compact = 180,
  }) => MediaQuery.sizeOf(context).width >= medium ? 24 : compact;

  const BzBreakpoints._();
}
