import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';
import 'glass/bz_glass.dart';

/// Compatibility facade for Breezze's single V8 Liquid Glass renderer.
///
/// This is intentionally NOT a second renderer. Every former
/// BzGlassContainer call now draws through [BzGlass] with the same
/// accessibility fallback and blur-budget behavior as the new design.
/// Legacy constructor parameters remain supported while screens migrate.
/// Do not implement independent ImageFilter/BackdropFilter effects here.
class BzGlassContainer extends StatelessWidget {
  const BzGlassContainer({
    super.key,
    required this.child,
    required this.radius,
    this.blur = 24,
    this.saturation = 180,
    this.fillColor,
    this.borderColor,
    this.reduceTransparency = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final double saturation;
  final Color? fillColor;
  final Color? borderColor;
  final bool reduceTransparency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    return BzGlass(
      state: BzGlassState.pillScrolled,
      radius: radius,
      sigmaOverride: blur,
      saturationOverride: saturation / 100,
      tintOverride: fillColor ?? colors.atmoRegular,
      borderOverride: borderColor ?? colors.separator,
      quality: reduceTransparency ? BzGlassQuality.solid : null,
      child: child,
    );
  }
}

/// Saturation color matrix (20-element row-major list) for the standard
/// luminance-preserving saturate transform (s = saturationPercent / 100).
///
/// Exposed so platform code that composes its own `ColorFiltered` can
/// reuse the exact same matrix, keeping the material identical across
/// surfaces that filter foreground content (artwork overlays, chips).
List<double> saturateMatrix(double saturationPercent) {
  final s = saturationPercent / 100.0;
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  final sr = (1 - s) * lumR, sg = (1 - s) * lumG, sb = (1 - s) * lumB;
  return <double>[
    sr + s, sg,     sb,     0, 0,
    sr,     sg + s, sb,     0, 0,
    sr,     sg,     sb + s, 0, 0,
    0,      0,      0,      1, 0,
  ];
}

/// Convenience: the saturate matrix from [saturateMatrix] as a ready-to-
/// use [ColorFilter] for `ColorFiltered` widgets that filter foreground
/// content with the same material recipe the glass surfaces use.
ColorFilter saturateColorFilter(double saturationPercent) =>
    ColorFilter.matrix(saturateMatrix(saturationPercent));
