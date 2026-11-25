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

/// One authoritative component theme for every Breezze screen.
///
/// Keeping control geometry and focus cues here prevents authentication,
/// discovery, library, search, settings and player sheets from drifting apart.
/// Semantic colors come from [BzThemeColors]; no duplicated screen palettes.
ThemeData _bzTheme({required bool dark}) {
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final c = dark ? BzThemeColors.dark : BzThemeColors.light;
  final typography = base.textTheme.copyWith(
    displayMedium: base.textTheme.displayMedium?.copyWith(
      fontSize: BzType.display,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.10,
    ),
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontSize: BzType.largeTitle,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9,
      height: 1.15,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: BzType.title2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: BzType.headline,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontSize: BzType.body,
      height: 1.35,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontSize: BzType.subheadline,
      height: 1.35,
    ),
  ).apply(bodyColor: c.text1, displayColor: c.text1);

  const minimumTapTarget = Size(44, 48);
  final inputShape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(BzRadius.input),
    borderSide: BorderSide(color: c.separator),
  );

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
    textTheme: typography,
    dividerColor: c.separator,
    iconTheme: IconThemeData(color: c.text1),
    appBarTheme: AppBarThemeData(
      backgroundColor: c.background,
      foregroundColor: c.text1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: typography.titleLarge?.copyWith(color: c.text1),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.surface1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: inputShape,
      enabledBorder: inputShape,
      focusedBorder: inputShape.copyWith(
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: inputShape.copyWith(
        borderSide: BorderSide(color: c.error),
      ),
      focusedErrorBorder: inputShape.copyWith(
        borderSide: BorderSide(color: c.error, width: 2),
      ),
      hintStyle: TextStyle(color: c.text2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.background,
        minimumSize: minimumTapTarget,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BzRadius.input),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text1,
        minimumSize: minimumTapTarget,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        side: BorderSide(color: c.separator),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BzRadius.input),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.text1,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BzRadius.button),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: c.text1,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface1,
      surfaceTintColor: Colors.transparent,
      elevation: BzElevation.level0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BzRadius.card),
        side: BorderSide(color: c.separator, width: 0.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.elevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BzRadius.sheet),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface1,
      modalBackgroundColor: c.elevated,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BzRadius.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.elevated,
      contentTextStyle: TextStyle(color: c.text1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BzRadius.input),
      ),
    ),
  );
}

/// Semantic light and dark modes share identical component geometry.
ThemeData bzLightTheme() => _bzTheme(dark: false);
ThemeData bzDarkTheme() => _bzTheme(dark: true);

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
