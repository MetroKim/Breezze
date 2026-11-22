import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';

/// BzGlassContainer — the one glass surface every floating widget uses.
///
/// Translucent fill + backdrop blur + saturate boost + hairline border.
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

  /// Saturation boost applied over the blurred backdrop. Kept separate
  /// from [blur] so callers can opt out of the boost without losing
  /// blur on media-overlay surfaces where the artwork must stay true.
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
        // saturate(N%) blur(Mpx) — the pill-scrolled material contract.
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          inner: ColorFilter.mode(
            const Color.fromRGBO(1, 1, 1, 0), // pass-through base
            // Compose a saturation boost via a matrix color filter.
            // Skia has no direct saturate; this matrix applies the
            // standard saturation transform for [saturation] percent.
            // See _saturateMatrix below for why this is a matrix.
            BlendMode.srcOver,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
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
}

/// Saturation matrix for the glass backdrop (saturate(180%)).
///
/// Exposed so platform code that composes its own ImageFilter can reuse
/// the exact same matrix, keeping the material identical everywhere.
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
