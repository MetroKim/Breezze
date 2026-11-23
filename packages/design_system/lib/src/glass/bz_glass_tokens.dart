import 'package:material_ui/material_ui.dart';

/// Extended Liquid Glass palette (BREEZZE_LIQUID_GLASS_EXTENDED §2.1).
///
/// These tokens are additive to the legacy §21.1 tokens in `tokens.dart`:
/// the shell and chrome migrate onto them in Phase 1, while existing
/// screens keep compiling against the legacy palette.
class BzLiquidColorsLight {
  static const ground = Color(0xFFF5F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHover = Color(0xFFFBFBFD);
  static const textPrimary = Color(0xFF1D1D1F);
  static const textBody = Color(0xFF424245);
  static const textSecondary = Color(0xFF6E6E73);
  static const textTertiary = Color(0xFF86868B);
  static const textQuaternary = Color(0xFFAEAEB2);
  static const accent = Color(0xFF0071E3);
  static const accentOnTint = Color(0xFF0066CC);
  static const hairline = Color(0x12000000); // rgba(0,0,0,0.07)
  static const live = Color(0xFF30D158);
}

class BzLiquidColorsDark {
  static const ground = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceHover = Color(0xFF2C2C2E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textBody = Color(0xD9FFFFFF); // white @ 85%
  static const textSecondary = Color(0xA6FFFFFF); // white @ 65%
  static const textTertiary = Color(0x73FFFFFF); // white @ 45%
  static const textQuaternary = Color(0x4DFFFFFF); // white @ 30%
  static const accent = Color(0xFF0A84FF);
  static const accentOnTint = Color(0xFF409CFF);
  static const hairline = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const live = Color(0xFF30D158);
}

/// Base colors the glass tints derive from per brightness.
class BzGlassBase {
  static const light = Color(0xFFFFFFFF);
  static const dark = Color(0xFF1C1C1E);
}

/// Glass depth — soft lift + specular top edge, never hard drop shadows
/// (§2.4).
class BzGlassShadows {
  /// 0 8px 32px rgba(0,0,0,0.12) — floating player, side panel.
  static const glassSoft = BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0, 8),
    blurRadius: 32,
  );

  /// 0 12px 48px rgba(0,0,0,0.18) — modal, overlay chrome.
  static const glassMedium = BoxShadow(
    color: Color(0x2E000000),
    offset: Offset(0, 12),
    blurRadius: 48,
  );

  /// Inset top-edge highlight: rgba(255,255,255,0.15).
  static const specular = Color(0x26FFFFFF);
}

/// The hairline rim every glass surface draws on its non-specular edges.
class BzGlassEdge {
  static const width = 0.5;
  static const color = Color(0x1AFFFFFF); // white @ 10%
}

/// Semantic radius scale (§2.3): 4 / 8 / 12 / 20 / 32 / pill.
class BzLiquidRadius {
  static const sm = 4.0; // badges, quality chips
  static const regular = 8.0; // buttons, list rows
  static const md = 12.0; // cards, search field
  static const lg = 20.0; // floating panels, sheets
  static const xl = 32.0; // large immersive overlays
  static const pill = 9999.0; // pills, tab indicators
}

/// Signature gradients — hero art and primary CTA only (§2.1). Forbidden
/// as full-bleed washes.
class BzLiquidGradients {
  /// Blue-to-indigo: linear-gradient(135deg, #0a84ff, #5e5ce6).
  static const heroBlueIndigo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
  );

  /// Warm-to-heat: linear-gradient(135deg, #ff9f0a, #ff375f).
  static const heroWarmHeat = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9F0A), Color(0xFFFF375F)],
  );
}

extension BzLiquidColorsX on BuildContext {
  /// Whether the active theme is dark.
  bool get bzIsDark => Theme.of(this).brightness == Brightness.dark;

  /// The extended Liquid palette for the active brightness (§2.1).
  Color get bzLiquidGround =>
      bzIsDark ? BzLiquidColorsDark.ground : BzLiquidColorsLight.ground;
  Color get bzLiquidSurface =>
      bzIsDark ? BzLiquidColorsDark.surface : BzLiquidColorsLight.surface;
  Color get bzLiquidAccent =>
      bzIsDark ? BzLiquidColorsDark.accent : BzLiquidColorsLight.accent;
  Color get bzLiquidHairline =>
      bzIsDark ? BzLiquidColorsDark.hairline : BzLiquidColorsLight.hairline;
}
