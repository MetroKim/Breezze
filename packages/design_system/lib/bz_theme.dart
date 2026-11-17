import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

/// Breezze theme — builds light/dark [ThemeData] purely from semantic
/// tokens (§21.1). Components consume [BzThemeExt] for material classes.
extension BzThemeExt on ThemeData {
  bool get isDark => brightness == Brightness.dark;
  Color get bzBackground => isDark ? BzColorsDark.background : BzColorsLight.background;
  Color get bzSurface1 => isDark ? BzColorsDark.surfacePrimary : BzColorsLight.surfacePrimary;
  Color get bzSurface2 => isDark ? BzColorsDark.surfaceSecondary : BzColorsLight.surfaceSecondary;
  Color get bzSurfaceElevated => isDark ? BzColorsDark.surfaceElevated : BzColorsLight.surfaceElevated;
  Color get bzText1 => isDark ? BzColorsDark.textPrimary : BzColorsLight.textPrimary;
  Color get bzText2 => isDark ? BzColorsDark.textSecondary : BzColorsLight.textSecondary;
  Color get bzSeparator => isDark ? BzColorsDark.separator : BzColorsLight.separator;
  Color get bzAccent => isDark ? BzColorsDark.accent : BzColorsLight.accent;
  Color get bzSuccess => isDark ? BzColorsDark.success : BzColorsLight.success;
  Color get bzWarning => isDark ? BzColorsDark.warning : BzColorsLight.warning;
  Color get bzError => isDark ? BzColorsDark.error : BzColorsLight.error;
  Color get bzAtmoRegular => isDark ? BzColorsDark.atmoRegular : BzColorsLightAtmo.atmoRegular;
  Color get bzAtmoClear => isDark ? BzColorsDark.atmoClear : BzColorsLightAtmo.atmoClear;
  Color get bzSoftDiffuse => isDark ? BzColorsDark.softDiffuse : BzColorsLightAtmo.softDiffuse;
}

/// Builds the Breezze light theme from tokens.
ThemeData bzLightTheme() {
  final scheme = ColorScheme.light(
    primary: BzColorsLight.textPrimary,
    onPrimary: BzColorsLight.background,
    secondary: BzColorsLight.accent,
    onSecondary: BzColorsLight.background,
    surface: BzColorsLight.surfacePrimary,
    onSurface: BzColorsLight.textPrimary,
    surfaceContainerHighest: BzColorsLight.surfaceSecondary,
    error: BzColorsLight.error,
    onError: BzColorsLight.background,
    outline: BzColorsLight.separator,
  );
  return _bzTheme(scheme, Brightness.light);
}

/// Builds the Breezze dark theme from tokens.
ThemeData bzDarkTheme() {
  final scheme = ColorScheme.dark(
    primary: BzColorsDark.textPrimary,
    onPrimary: BzColorsDark.background,
    secondary: BzColorsDark.accent,
    onSecondary: BzColorsDark.background,
    surface: BzColorsDark.surfacePrimary,
    onSurface: BzColorsDark.textPrimary,
    surfaceContainerHighest: BzColorsDark.surfaceSecondary,
    error: BzColorsDark.error,
    onError: BzColorsDark.background,
    outline: BzColorsDark.separator,
  );
  return _bzTheme(scheme, Brightness.dark);
}

ThemeData _bzTheme(ColorScheme scheme, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = isDark ? bzDarkTheme() : bzLightTheme();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? BzColorsDark.background : BzColorsLight.background,
    textTheme: _bzTextTheme(brightness),
    splashFactory: InkSparkle.splashFactory,
  );
}

TextTheme _bzTextTheme(Brightness brightness) {
  final color = brightness == Brightness.dark ? BzColorsDark.textPrimary : BzColorsLight.textPrimary;
  const font = 'System';
  return TextTheme(
    displayLarge: TextStyle(fontSize: BzType.display, fontWeight: FontWeight.w700, color: color, fontFamily: font),
    displayMedium: TextStyle(fontSize: BzType.largeTitle, fontWeight: FontWeight.w700, color: color, fontFamily: font),
    headlineMedium: TextStyle(fontSize: BzType.title1, fontWeight: FontWeight.w700, color: color, fontFamily: font),
    headlineSmall: TextStyle(fontSize: BzType.title2, fontWeight:.w600, color: color, fontFamily: font),
    titleLarge: TextStyle(fontSize: BzType.title3, fontWeight: FontWeight.w600, color: color, fontFamily: font),
    titleMedium: TextStyle(fontSize: BzType.headline, fontWeight: FontWeight.w600, color: color, fontFamily: font),
    bodyLarge: TextStyle(fontSize: BzType.body, color: color, fontFamily: font),
    bodyMedium: TextStyle(fontSize: BzType.subheadline, color: color, fontFamily: font),
    bodySmall: TextStyle(fontSize: BzType.footnote, color: color, fontFamily: font),
    labelSmall: TextStyle(fontSize: BzType.caption, color: color, fontFamily: font),
  );
}
