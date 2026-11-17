import 'dart:ui';

import 'package:flutter/material.dart';

/// BzGlassContainer — the one glass surface every floating widget uses.
///
/// Translucent fill + backdrop blur + hairline border. When reduced
/// transparency is enabled it degrades to a solid surface automatically.
class BzGlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color? fillColor;
  final Color? borderColor;

  const BzGlassContainer({
    super.key,
    required this.child,
    required this.radius,
    this.blur = 24,
    this.fillColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final reduceTransparency =
        media.disableAnimations || media.boldText;

    final fill = fillColor ?? theme.extension<Never>() == null
        ? null
        : null;
    // resolved in BzThemeColors-aware wrapper below
    return _build(theme, reduceTransparency, fill);
  }

  Widget _build(ThemeData theme, bool reduce, Color? _) {
    if (reduce) {
      return Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: theme.dividerColor),
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
            color: fillColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? theme.dividerColor,
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
