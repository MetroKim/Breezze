import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';

/// BzGlassContainer — the one glass surface every floating widget uses.
///
/// Translucent fill + backdrop blur + saturation boost + hairline border.
/// The saturate(180%) boost is not optional: without it the material
/// reads as generic translucency rather than a deliberate glass system.
///
/// Bar-spawned surfaces (menus, popovers, dialogs) must NOT use this
/// widget: they are near-opaque, blur-free solids by contract — stacking
/// glass on glass makes the lower surface meaningless and breaks the
/// two-blurred-surface-per-viewport budget.
///
/// Degrades to a solid surface when the caller requests reduced
/// transparency or the platform enables high-contrast mode.
class BzGlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color? fillColor;
  final Color? borderColor;
  final bool reduceTransparency;

  /// Saturation boost for the glass material (180 = the spec default).
  ///
  /// Flutter's stable backdrop pipeline only supports geometric filters
  /// (blur/dilate/erode) on the backdrop — there is no color stage — so
  /// the CSS `saturate(180%)` half of the pill-scrolled recipe is applied
  /// to the translucent fill tint that overlays the blurred backdrop
  /// instead. The fill is what the eye reads as "the glass", so its
  /// saturation carries the material's warmth through.
  final double saturation;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.bz;

    final fill = fillColor ?? colors.atmoRegular;
    final border = borderColor ?? colors.separator;

    final useSolidSurface = reduceTransparency ||
        MediaQuery.highContrastOf(context);

    if (useSolidSurface) {
      return Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        // blur(Mpx) — the geometric half of the pill-scrolled material
        // contract. The saturate(N%) half lives in the fill tint below
        // (Flutter has no backdrop color stage in its stable API).
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _saturatedFill(fill),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 0.5),
            gradient: const LinearGradient(
              // Specular top-edge highlight: --shadow-specular.
              begin: Alignment.topCenter,
              end: Alignment(0.0, 0.04),
              colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
            ),
            boxShadow: const [
              // --shadow-glass-soft: gentle lift, never a hard drop.
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 32,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  /// Flutter-safe approximation of the CSS `saturate(N%)` backdrop stage:
  /// boost the saturation of the translucent fill overlaying the blurred
  /// backdrop. A 100% value is a pass-through.
  Color _saturatedFill(Color base) {
    if (saturation == 100) return base;
    final hsl = HSLColor.fromColor(base);
    // num.clamp() returns num, not double — the explicit toDouble() is
    // required for withSaturation(double).
    final boosted =
        (hsl.saturation * saturation / 100).clamp(0.0, 1.0).toDouble();
    return hsl.withSaturation(boosted).toColor();
  }
}

/// Saturation color matrix for the standard luminance-preserving
/// saturate transform (s = saturationPercent / 100).
///
/// Exposed so platform code that composes its own `ColorFiltered` can
/// reuse the exact same matrix, keeping the material identical across
/// surfaces that filter foreground content (artwork overlays, chips).
ColorMatrix saturateMatrix(double saturationPercent) {
  final s = saturationPercent / 100.0;
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  final sr = (1 - s) * lumR, sg = (1 - s) * lumG, sb = (1 - s) * lumB;
  return ColorMatrix.fromList(<double>[
    sr + s, sg,     sb,     0, 0,
    sr,     sg + s, sb,     0, 0,
    sr,     sg,     sb + s, 0, 0,
    0,      0,      0,      1, 0,
  ]);
}
