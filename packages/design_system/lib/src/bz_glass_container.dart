import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';

/// BzGlassContainer — the one glass surface every floating widget uses.
///
/// Translucent fill + backdrop blur + hairline border. Degrades to a
/// solid surface when the caller requests reduced transparency or the
/// platform enables high-contrast accessibility mode.
class BzGlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color? fillColor;
  final Color? borderColor;
  final bool reduceTransparency;

  const BzGlassContainer({
    super.key,
    required this.child,
    required this.radius,
    this.blur = 24,
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
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}
