/// Single source of truth for the Breezze theme.
///
/// The theme used to live in two places: this file carried a parallel
/// set of colors and builders that drifted from the ThemeExtension
/// version under src/. Any app that imported both got conflicting
/// extension members. This barrel now re-exports src/bz_theme.dart so
/// both import paths resolve to one implementation.
library;

export 'src/bz_theme.dart';
export 'src/tokens.dart';
