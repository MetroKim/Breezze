import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Breezze theme — spec §21.
///
/// Builds the light and dark Material themes from the §21.1 tokens, and
/// exposes the semantic Breezze colors as ThemeData extensions so screens
/// consume only tokens (no literal colors anywhere else).
///
/// This file was missing from the branch while the barrel exported it —
/// the root cause of the analyzer error cascade.

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
    );
  }
}

/// One product-wide theme contract for every page, sheet and control.
///
/// Flutter's base themes include platform-colored defaults that would leak
/// blue/purple into buttons, text inputs and segmented controls. Centralizing
/// overrides here keeps the supplied black/grey/white palette consistent.
ThemeData _productTheme(ThemeData base, BzThemeColors c) {
  final foreground = c.text1;
  final background = c.background;
  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: background,
    canvasColor: background,
    cardColor: c.surface1,
    dialogTheme: DialogThemeData(backgroundColor: c.surface1),
    splashColor: foreground.withValues(alpha: 0.06),
    highlightColor: foreground.withValues(alpha: 0.04),
    dividerColor: c.separator,
    colorScheme: base.colorScheme.copyWith(
      primary: foreground,
      onPrimary: background,
      secondary: foreground,
      onSecondary: background,
      primaryContainer: c.surface2,
      onPrimaryContainer: foreground,
      secondaryContainer: c.surface2,
      onSecondaryContainer: foreground,
      surface: c.surface1,
      onSurface: foreground,
      surfaceContainerHighest: c.surface2,
      onSurfaceVariant: c.text2,
      outline: c.separator,
      outlineVariant: c.separator,
      error: c.error,
      onError: c.surface1,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ).copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: -1.8,
        color: foreground,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: -1.25,
        color: foreground,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.65,
        color: foreground,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.45,
        color: foreground,
      ),
    ),
    iconTheme: IconThemeData(color: foreground, size: 22),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      hintStyle: TextStyle(color: c.text2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BzRadius.input),
        borderSide: BorderSide(color: c.separator),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BzRadius.input),
        borderSide: BorderSide(color: c.separator),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BzRadius.input),
        borderSide: BorderSide(color: foreground, width: 1.25),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: foreground,
        foregroundColor: background,
        disabledBackgroundColor: c.surface2,
        disabledForegroundColor: c.text2,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BzRadius.button),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.surface1,
        foregroundColor: foreground,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BzRadius.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: c.separator),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BzRadius.button),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: foreground),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.text2,
      textColor: foreground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BzRadius.button),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface1,
      indicatorColor: c.surface2,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.surface1,
      selectedItemColor: foreground,
      unselectedItemColor: c.text2,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: foreground,
      inactiveTrackColor: c.separator,
      thumbColor: foreground,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? background : c.text2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? foreground : c.surface2,
      ),
    ),
  );
}

ThemeData bzLightTheme() =>
    _productTheme(ThemeData.light(useMaterial3: true), BzThemeColors.light);

ThemeData bzDarkTheme() =>
    _productTheme(ThemeData.dark(useMaterial3: true), BzThemeColors.dark);

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
  Color get bzSeparator => bz.separator;
  Color get bzAccent => bz.accent;
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
