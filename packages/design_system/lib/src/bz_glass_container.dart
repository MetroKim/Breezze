import 'package:material_ui/material_ui.dart';

import 'bz_glass_material.dart';
import 'bz_theme.dart';

/// BzGlassContainer — legacy glass surface, now delegating to the named
/// Liquid Glass materials (§2.2).
///
/// The public API is preserved for existing call sites. The legacy
/// parameters map onto the material contract:
/// - default fill (atmoRegular) → [BzGlassState.pillScrolled]
/// - atmoClear / softDiffuse fill → [BzGlassState.mediaOverlay]
/// - a blur of 12 or less over a calm zone → [BzGlassState.pillAtTop]
///
/// The old recipe (generic blur 24, no saturation boost) is retired: the
/// saturation boost is what separates Liquid Glass from generic
/// translucency.
class BzGlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;

  /// Legacy. The material contract now owns blur; values <= 12 select
  /// the pillAtTop material, anything larger selects the state derived
  /// from the fill color.
  final double blur;

  /// Legacy. When null (the default) the theme's pill-scrolled fill is
  /// used. When it matches the theme's media-overlay fill the
  /// media-overlay material is selected.
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
    final colors = Theme.of(context).bz;
    final fill = fillColor;
    final isMediaOverlayFill = fill != null &&
        (fill.toARGB32() == colors.atmoClear.toARGB32() ||
            fill.toARGB32() == colors.softDiffuse.toARGB32());

    final BzGlassState state;
    if (isMediaOverlayFill) {
      state = blur <= 12 ? BzGlassState.pillAtTop : BzGlassState.mediaOverlay;
    } else {
      state = blur <= 12 ? BzGlassState.pillAtTop : BzGlassState.pillScrolled;
    }

    return BzGlassMaterial(
      state: state,
      radius: radius,
      reduceTransparency: reduceTransparency,
      shadows: const [],
      child: child,
    );
  }
}
