import 'package:material_ui/material_ui.dart';

/// Breezze design tokens — spec §21.1.
///
/// Semantic tokens only. No literal colors are allowed anywhere else in
/// the app; every surface, text, and control consumes these.
///
/// 2026-11 revision ("Liquid Glass" alignment):
/// - Light mode ground is a cool grey (#f5f5f7), never warm cream.
/// - Dark mode collapses to pure black (#000000) for OLED efficiency.
/// - Accent is a single blue family (#0071e3 light / #0a84ff dark),
///   reserved for primary music actions and active navigation only.
/// - Separators are hairlines (7% black / 10% white), not solid greys.
/// - Accent is NEVER used as a background wash.
class BzColorsLight {
  static const background = Color(0xFFF5F5F7); // cool ground
  static const surfacePrimary = Color(0xFFFFFFFF); // cards, sheets, panels
  static const surfaceSecondary = Color(0xFFFBFBFD); // hover, secondary buttons
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1D1D1F);
  static const textSecondary = Color(0xFF6E6E73);
  static const textTertiary = Color(0xFF86868B);
  static const separator = Color(0x12000000); // 7% black hairline
  static const brandMonochrome = Color(0xFF1D1D1F);
  static const accent = Color(0xFF0071E3); // light-mode Apple blue
  static const accentOnTint = Color(0xFF0066CC);
  static const live = Color(0xFF30D158);
  static const success = Color(0xFF237A4B);
  static const warning = Color(0xFF98620E);
  static const error = Color(0xFFB42332);
}

class BzColorsDark {
  static const background = Color(0xFF000000); // OLED pure black
  static const surfacePrimary = Color(0xFF1C1C1E); // cards, sheets, panels
  static const surfaceSecondary = Color(0xFF2C2C2E); // hover, secondary buttons
  static const surfaceElevated = Color(0xFF1C1C1E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B8); // ~rgba(255,255,255,0.7)
  static const textTertiary = Color(0xFF737378); // ~rgba(255,255,255,0.45)
  static const separator = Color(0x1AFFFFFF); // 10% white hairline
  static const brandOnDark = Color(0xFFFFFFFF);
  static const accent = Color(0xFF0A84FF); // dark-mode Apple blue
  static const accentOnTint = Color(0xFF409CFF);
  static const live = Color(0xFF30D158);
  static const success = Color(0xFF55C88A);
  static const warning = Color(0xFFEAB95C);
  static const error = Color(0xFFFF6574);

  // Atmosphere material overlays (§20.1)
  // pill-scrolled state: 85-95% near-opaque surface + saturate/blur.
  static const atmoRegular = Color(0xE01C1C1E); // 88% surface-1
  // clear state: sparse large controls over rich media only.
  static const atmoClear = Color(0x2E000000); // 18% background
  // media-overlay: demoted overlay-chrome recipe (55%).
  static const softDiffuse = Color(0x8C1C1C1E); // 55% surface-1
}

class BzColorsLightAtmo {
  // pill-scrolled light equivalent: 88% white + blur.
  static const atmoRegular = Color(0xE0FFFFFF); // 88% white
  static const atmoClear = Color(0x2EF5F5F7); // 18% ground
  static const softDiffuse = Color(0x8CFFFFFF); // 55% white
}

/// Spacing — 8pt grid, 4pt micro (§21.5).
class BzSpacing {
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
}

/// Radius (§21.6).
class BzRadius {
  static const double button = 8; // buttons, list rows, sidebar selection
  static const double input = 12; // search field
  static const double artwork = 12; // artwork cards
  static const double card = 12;
  static const double sheet = 20; // floating panels, bottom sheets
  static const double modal = 32; // large immersive overlays
  static const double capsule = 999; // search pill, player pill, tab indicator
}

/// Elevation (§21.7).
class BzElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 2;
  static const double level3 = 3;
  static const double level4 = 4;
  static const double level5 = 5;
}

/// Motion (§20.7/§21.10).
class BzMotion {
  static const int instantMs = 100;
  static const int fastMs = 160;
  static const int navMs = 240;
  static const int artworkMs = 360;
  static const int expandMs = 420;
  static const int sheetMs = 320;
  static const int morphMs = 450;

  /// Scroll-adaptive bars animate background-color/opacity ONLY
  /// (never size, radius, padding, or layout on a blurred bar).
  static const int barAdaptMs = 200;
}

/// Type scale (§21.3).
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

/// Shared responsive breakpoints for the adaptive Flutter shell.
class BzBreakpoints {
  static const double compact = 600;
  static const double medium = 810;
  static const double expanded = 1200;
  static const double wide = 1600;
  static const double contentMaxWidth = 1440;

  /// Bottom clearance reserved for the persistent mini-player/navigation.
  /// Desktop places playback in the shell footer, so content needs less room.
  static double bottomClearance(
    BuildContext context, {
    double compact = 180,
  }) => MediaQuery.sizeOf(context).width >= medium ? 24 : compact;

  const BzBreakpoints._();
}
