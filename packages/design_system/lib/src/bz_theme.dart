import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Breezze theme — Apple Music "Liquid Glass" contract.
///
/// Builds the light and dark Material themes from the §2.1 tokens, and
/// exposes the semantic Breezze colors as ThemeData extensions so screens
/// consume only tokens (no literal colors anywhere else).

/// Semantic Breezze colors for the active theme (light or dark).
class BzThemeColors extends ThemeExtension<BzThemeColors> {
  final Color background;
  final Color surface1;
  final Color surface2;
  final Color elevated;
  final Color text1;
  final Color text2;
  final Color separator;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;

  /// Atmosphere material overlays (§20.1): 72% surface, 18% clear.
  final Color atmoRegular;
  final Color atmoClear;
  final Color softDiffuse;

  // Liquid Glass additions (§2.1).
  final Color text3; // --color-text-tertiary: captions, quality badges
  final Color text4; // --color-text-quaternary: placeholders, faint numbers
  final Color hairline; // --color-hairline: dividers, list separators
  final Color accentOnTint; // --color-accent-on-tint

  const BzThemeColors({
    required this.background,
    required this.surface1,
    required this.surface2,
    required this.elevated,
    required this.text1,
    required this.text2,
    required this.separator,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.atmoRegular,
    required this.atmoClear,
    required this.softDiffuse,
    required this.text3,
    required this.text4,
    required this.hairline,
    required this.accentOnTint,
  });

  static const light = BzThemeColors(
    background: BzColorsLight.background,
    surface1: BzColorsLight.surfacePrimary,
    surface2: BzColorsLight.surfaceSecondary,
    elevated: BzColorsLight.surfaceElevated,
    text1: BzColorsLight.textPrimary,
    text2: BzColorsLight.textSecondary,
    separator: BzColorsLight.separator,
    accent: BzColorsLight.accent,
    success: BzColorsLight.success,
    warning: BzColorsLight.warning,
    error: BzColorsLight.error,
    atmoRegular: BzColorsLightAtmo.atmoRegular,
    atmoClear: BzColorsLightAtmo.atmoClear,
    softDiffuse: BzColorsLightAtmo.softDiffuse,
    text3: BzColorsLight.textTertiary,
    text4: BzColorsLight.textQuaternary,
    hairline: BzColorsLight.separator,
    accentOnTint: BzColorsLight.accentOnTint,
  );

  static const dark = BzThemeColors(
    background: BzColorsDark.background,
    surface1: BzColorsDark.surfacePrimary,
    surface2: BzColorsDark.surfaceSecondary,
    elevated: BzColorsDark.surfaceElevated,
    text1: BzColorsDark.textPrimary,
    text2: BzColorsDark.textSecondary,
    separator: BzColorsDark.separator,
    accent: BzColorsDark.accent,
    success: BzColorsDark.success,
    warning: BzColorsDark.warning,
    error: BzColorsDark.error,
    atmoRegular: BzColorsDark.atmoRegular,
    atmoClear: BzColorsDark.atmoClear,
    softDiffuse: BzColorsDark.softDiffuse,
    text3: BzColorsDark.textTertiary,
    text4: BzColorsDark.textQuaternary,
    hairline: BzColorsDark.separator,
    accentOnTint: BzColorsDark.accentOnTint,
  );

  @override
  BzThemeColors copyWith({
    Color? background,
    Color? surface1,
    Color? surface2,
    Color? elevated,
    Color? text1,
    Color? text2,
    Color? separator,
    Color? accent,
    Color? success,
    Color? warning,
    Color? error,
    Color? atmoRegular,
    Color? atmoClear,
    Color? softDiffuse,
    Color? text3,
    Color? text4,
    Color? hairline,
    Color? accentOnTint,
  }) {
    return BzThemeColors(
      background: background ?? this.background,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      elevated: elevated ?? this.elevated,
      text1: text1 ?? this.text1,
      text2: text2 ?? this.text2,
      separator: separator ?? this.separator,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      atmoRegular: atmoRegular ?? this.atmoRegular,
      atmoClear: atmoClear ?? this.atmoClear,
      softDiffuse: softDiffuse ?? this.softDiffuse,
      text3: text3 ?? this.text3,
      text4: text4 ?? this.text4,
      hairline: hairline ?? this.hairline,
      accentOnTint: accentOnTint ?? this.accentOnTint,
    );
  }

  @override
  BzThemeColors lerp(BzThemeColors? other, double t) {
    if (other == null) return this;
    return BzThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      text1: Color.lerp(text1, other.text1, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      atmoRegular: Color.lerp(atmoRegular, other.atmoRegular, t)!,
      atmoClear: Color.lerp(atmoClear, other.atmoClear, t)!,
      softDiffuse: Color.lerp(softDiffuse, other.softDiffuse, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      text4: Color.lerp(text4, other.text4, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accentOnTint: Color.lerp(accentOnTint, other.accentOnTint, t)!,
    );
  }
}

/// The light theme, §21.2.
ThemeData bzLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final c = BzThemeColors.light;
  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.background,
    colorScheme: base.colorScheme.copyWith(
      primary: c.text1,
      onPrimary: c.background,
      secondary: c.accent,
      onSurface: c.text1,
      onSurfaceVariant: c.text2,
      surface: c.surface1,
      error: c.error,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: c.text1,
      displayColor: c.text1,
    ),
    dividerColor: c.separator,
  );
}

/// The dark theme, §21.2.
ThemeData bzDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final c = BzThemeColors.dark;
  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.background,
    colorScheme: base.colorScheme.copyWith(
      primary: c.text1,
      onPrimary: c.background,
      secondary: c.accent,
      onSurface: c.text1,
      onSurfaceVariant: c.text2,
      surface: c.surface1,
      error: c.error,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: c.text1,
      displayColor: c.text1,
    ),
    dividerColor: c.separator,
  );
}

/// Reads the Breezze colors off any BuildContext — the one accessor every
/// screen uses.
extension BzThemeX on ThemeData {
  BzThemeColors get bz => extension<BzThemeColors>()!;

  // Short aliases used across the screens.
  Color get bzBackground => bz.background;
  Color get bzSurface1 => bz.surface1;
  Color get bzSurface2 => bz.surface2;
  Color get bzText1 => bz.text1;
  Color get bzText2 => bz.text2;
  Color get bzText3 => bz.text3;
  Color get bzText4 => bz.text4;
  Color get bzHairline => bz.hairline;
  Color get bzSeparator => bz.separator;
  Color get bzAccent => bz.accent;
  Color get bzAccentOnTint => bz.accentOnTint;
  Color get bzError => bz.error;
  Color get bzSuccess => bz.success;
  Color get bzWarning => bz.warning;
  Color get bzAtmoRegular => bz.atmoRegular;
  Color get bzAtmoClear => bz.atmoClear;
  Color get bzSoftDiffuse => bz.softDiffuse;
}

/// Convenience: colors directly from a BuildContext.
extension BzContextX on BuildContext {
  BzThemeColors get bzColors => Theme.of(this).bz;
}
