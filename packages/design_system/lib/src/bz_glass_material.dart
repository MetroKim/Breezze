import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';
import 'tokens.dart';

/// Named glass materials (§2.2). Glass is a behavioral contract, not a
/// generic transparency value.
///
/// | State        | Legal use                                    | Contract                                |
/// |--------------|----------------------------------------------|-----------------------------------------|
/// | pillAtTop    | Text-bearing top bar over a calm hero zone   | 70-80% opacity; no busy imagery beneath |
/// | pillScrolled | Default chrome once content can scroll under | 85-95% fill + blur 16 + saturate(180%)   |
/// | mediaOverlay | Media controls where art remains the subject | 55% fill, overlay chrome only           |
/// | clear        | Sparse, large controls over rich media only | No blur backing; tint/border only       |
///
/// Glass is reserved for navigation, overlays, and floating controls.
/// It is never used on content cards, article panels, or backgrounds.
enum BzGlassState { pillAtTop, pillScrolled, mediaOverlay, clear }

class _GlassContract {
  final double fillAlpha;
  final double blurSigma;
  final double saturation;
  final bool blurred;

  const _GlassContract({
    required this.fillAlpha,
    required this.blurSigma,
    required this.saturation,
    required this.blurred,
  });

  static const pillAtTop = _GlassContract(
    fillAlpha: 0.75,
    blurSigma: 10,
    saturation: 1.8,
    blurred: true,
  );

  static const pillScrolled = _GlassContract(
    fillAlpha: 0.88,
    blurSigma: 16,
    saturation: 1.8,
    blurred: true,
  );

  static const mediaOverlay = _GlassContract(
    fillAlpha: 0.55,
    blurSigma: 16,
    saturation: 1.6,
    blurred: true,
  );

  static const clear = _GlassContract(
    fillAlpha: 0.08,
    blurSigma: 0,
    saturation: 1.0,
    blurred: false,
  );

  static _GlassContract of(BzGlassState state) => switch (state) {
        BzGlassState.pillAtTop => pillAtTop,
        BzGlassState.pillScrolled => pillScrolled,
        BzGlassState.mediaOverlay => mediaOverlay,
        BzGlassState.clear => clear,
      };
}

/// The Liquid Glass blur budget (NFR-007): at most 2 visible blurred
/// surfaces per viewport. Stacking a third makes the lower one
/// meaningless. Enforced via the assert in BzGlassMaterial.
const int bzMaxVisibleBlurredSurfaces = 2;

int _activeBlurredSurfaces = 0;

/// BzGlassMaterial - renders one named Liquid Glass material.
///
/// The material fills with the theme surface at the state's alpha,
/// blurs the backdrop at the state's sigma with a saturation boost, and
/// adds the hairline border. It degrades to a blur-free solid surface
/// when the caller requests reduced transparency or the platform
/// enables high contrast.
///
/// One glass layer class per viewport region: never nest two of these.
class BzGlassMaterial extends StatefulWidget {
  final BzGlassState state;
  final Widget child;
  final double radius;

  /// Opt-out requested by the app when the user enables reduced
  /// transparency.
  final bool reduceTransparency;

  /// Floating surfaces lift with a depth shadow (§2.4). Pass an empty
  /// list to suppress (e.g. edge-to-edge nav chrome).
  final List<BoxShadow>? shadows;

  const BzGlassMaterial({
    super.key,
    required this.state,
    required this.child,
    this.radius = BzRadius.pill,
    this.reduceTransparency = false,
    this.shadows,
  });

  @override
  State<BzGlassMaterial> createState() => _BzGlassMaterialState();
}

class _BzGlassMaterialState extends State<BzGlassMaterial> {
  bool _blurred = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRegistration();
  }

  void _syncRegistration() {
    final contract = _GlassContract.of(widget.state);
    final solid = _useSolid();
    final shouldBlur = contract.blurred && !solid;
    if (shouldBlur == _blurred) return;
    if (shouldBlur) {
      _activeBlurredSurfaces++;
      assert(
        _activeBlurredSurfaces <= bzMaxVisibleBlurredSurfaces,
        'Liquid Glass budget exceeded: $_activeBlurredSurfaces blurred '
        'surfaces are active, but the maximum visible blurred surfaces '
        'per viewport is $bzMaxVisibleBlurredSurfaces (NFR-007). Merge, '
        'solidify, or demote one surface.',
      );
    } else {
      _activeBlurredSurfaces--;
    }
    _blurred = shouldBlur;
  }

  @override
  void dispose() {
    if (_blurred) {
      _activeBlurredSurfaces--;
      _blurred = false;
    }
    super.dispose();
  }

  bool _useSolid() =>
      widget.reduceTransparency ||
      MediaQuery.highContrastOf(context) ||
      MediaQuery.disableAnimationsOf(context);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    final contract = _GlassContract.of(widget.state);
    final useSolid = _useSolid();

    final fill = colors.surface1.withValues(alpha: contract.fillAlpha);
    final border = Border.all(color: colors.hairline, width: 0.5);
    final radius = BorderRadius.circular(widget.radius);
    final shadows = widget.shadows ?? const [BzShadow.glassSoft];

    if (useSolid || !contract.blurred) {
      return DecoratedBox(
        decoration: BoxDecoration(
          // Solid degrade keeps the surface legible and blur-free.
          color: contract.blurred ? colors.surface1 : fill,
          borderRadius: radius,
          border: contract.blurred ? null : border,
          boxShadow: contract.blurred ? null : shadows,
        ),
        child: widget.child,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // backdrop-filter: saturate(180%) blur(16px). The saturation
          // boost is not optional; without it the material reads as
          // generic translucency.
          filter: _filter(contract),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: border,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  ui.ImageFilter _filter(_GlassContract contract) {
    final blur = ui.ImageFilter.blur(
      sigmaX: contract.blurSigma,
      sigmaY: contract.blurSigma,
    );
    if (contract.saturation == 1.0) return blur;
    return ui.ImageFilter.compose(
      outer: blur,
      inner: ui.ImageFilter.colorFilter(
        ui.ColorFilter.matrix(_saturationMatrix(contract.saturation)),
      ),
    );
  }

  /// Saturation color matrix (row-major 5x4 RGBA transform).
  static List<double> _saturationMatrix(double s) {
    const lumR = 0.213;
    const lumG = 0.715;
    const lumB = 0.072;
    return [
      lumR + (1 - lumR) * s, lumG * (1 - s), lumB * (1 - s), 0, 0,
      lumR * (1 - s), lumG + (1 - lumG) * s, lumB * (1 - s), 0, 0,
      lumR * (1 - s), lumG * (1 - s), lumB + (1 - lumB) * s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// BzBarSurface - a surface spawned by a bar (dropdown, menu, popover).
///
/// Bar-spawned surfaces are unconditionally near-opaque, blur-free
/// solids. They never inherit the glass material of their parent bar;
/// stacking glass on glass makes the lower layer meaningless and burns
/// the blur budget.
class BzBarSurface extends StatelessWidget {
  final Widget child;
  final double radius;

  const BzBarSurface({
    super.key,
    required this.child,
    this.radius = BzRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.hairline, width: 0.5),
        boxShadow: const [BzShadow.glassMedium],
      ),
      child: child,
    );
  }
}
