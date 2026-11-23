import 'dart:async';
import 'dart:ui' show ColorFilter, ImageFilter, TileMode;

import 'package:material_ui/material_ui.dart';

import 'bz_glass_tokens.dart';

/// Liquid Glass material states (BREEZZE_LIQUID_GLASS_EXTENDED §2.2).
///
/// Glass is a named material with a behavioral contract, not a generic
/// transparency value:
///
/// - [pillAtTop] — text-bearing top bar over a calm hero zone: 72% tint,
///   blur(12), saturate(180%).
/// - [pillScrolled] — default chrome over scrollable content: 88% tint,
///   blur(16), saturate(180%). The saturate boost and blur radius here are
///   non-negotiable; without them the material reads as generic
///   translucency.
/// - [mediaOverlay] — media controls where the artwork remains the
///   subject: 55% tint, blur(14), saturate(150%).
/// - [clear] — sparse, large controls over rich media only: tint/border
///   only, no blur backing; never for text-heavy nav, menus, or body.
enum BzGlassState { pillAtTop, pillScrolled, mediaOverlay, clear }

/// Rendering quality tiers.
///
/// - [full] — saturate + blur + specular + shadow (default).
/// - [frost] — wider blur, no saturation boost: for devices that cannot
///   spare the extra filter pass.
/// - [solid] — plain opaque surface: the accessibility fallback, and the
///   shape every budget-demoted surface takes.
enum BzGlassQuality { full, frost, solid }

class _GlassRecipe {
  final double sigma;
  final double saturation;
  const _GlassRecipe({required this.sigma, required this.saturation});
}

const Map<BzGlassState, _GlassRecipe> _recipes = {
  BzGlassState.pillAtTop: _GlassRecipe(sigma: 12, saturation: 1.8),
  BzGlassState.pillScrolled: _GlassRecipe(sigma: 16, saturation: 1.8),
  BzGlassState.mediaOverlay: _GlassRecipe(sigma: 14, saturation: 1.5),
  BzGlassState.clear: _GlassRecipe(sigma: 0, saturation: 1.0),
};

/// The maximum blurred surfaces per viewport (NFR-007, PRT-09).
const int kBzGlassBlurBudgetDefault = 2;

/// Enforces the blur budget for a viewport region.
///
/// Wrap the shell (or any independent overlay region) in this. Blurred
/// [BzGlass] surfaces register with the nearest scope in mount order; the
/// first [maxVisibleSurfaces] render glass, any further surface is demoted
/// to a near-opaque solid and re-promoted automatically once a slot frees.
///
/// [BzGlassState.clear] surfaces never blur, so they never consume budget.
class BzGlassBudgetScope extends StatefulWidget {
  const BzGlassBudgetScope({
    super.key,
    this.maxVisibleSurfaces = kBzGlassBlurBudgetDefault,
    required this.child,
  }) : assert(maxVisibleSurfaces >= 1);

  final int maxVisibleSurfaces;
  final Widget child;

  static _BzGlassBudgetScopeState? _maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<_BzGlassBudgetScopeState>();

  @override
  State<BzGlassBudgetScope> createState() => _BzGlassBudgetScopeState();
}

class _BzGlassBudgetScopeState extends State<BzGlassBudgetScope> {
  final List<_BzGlassElement> _active = [];
  final List<VoidCallback> _listeners = [];
  bool _notifyScheduled = false;

  void register(_BzGlassElement surface) {
    assert(!_active.contains(surface), 'surface registered twice');
    _active.add(surface);
  }

  void release(_BzGlassElement surface) {
    _active.remove(surface);
    _scheduleNotify();
  }

  /// Mount-order index of [surface]; indexes below the budget keep glass.
  int grantOf(_BzGlassElement surface) => _active.indexOf(surface);

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Notify post-frame — [release] runs during teardown, when calling
  /// setState on sibling elements mid-build would throw.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The one glass surface chrome uses.
///
/// Renders the named [state] material: backdrop blur + saturation boost,
/// theme-adaptive tint, specular top edge, hairline rim, soft lift shadow.
///
/// Contracts enforced here, in one place (PRT-09):
///
/// - **Accessibility collapse** — `disableAnimations` (reduce motion) or
///   high-contrast mode renders an opaque solid surface instead. This is
///   the only answer to those settings; callers need not check.
/// - **Blur budget** — under a [BzGlassBudgetScope], a surface beyond the
///   budget demotes to a near-opaque solid (bar-spawned surfaces must be
///   blur-free solids anyway; this keeps the invariant machine-checked).
/// - **No layout morphing** — nothing in this widget animates size,
///   radius, padding, or layout; scroll-adaptive callers animate only the
///   tint color and opacity above it (§5).
class BzGlass extends StatefulWidget {
  const BzGlass({
    super.key,
    required this.state,
    this.radius = BzLiquidRadius.md,
    this.quality,
    this.shadow = true,
    this.child,
  });

  final BzGlassState state;
  final double radius;

  /// Quality override. Leave null to resolve from accessibility settings:
  /// reduce motion or high contrast force [BzGlassQuality.solid].
  final BzGlassQuality? quality;

  /// Whether to draw the soft glass lift shadow. Off for inline chrome.
  final bool shadow;

  final Widget? child;

  @override
  State<BzGlass> createState() => _BzGlassElement();
}

class _BzGlassElement extends State<BzGlass> {
  _BzGlassBudgetScopeState? _scope;
  bool _registered = false;
  VoidCallback? _onBudgetChanged;

  bool get _stateBlurs => _recipes[widget.state]!.sigma > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= BzGlassBudgetScope._maybeOf(context);
    if (_stateBlurs) {
      _ensureRegistered();
    } else {
      _maybeUnregister();
    }
  }

  @override
  void didUpdateWidget(BzGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBlurs = _recipes[oldWidget.state]!.sigma > 0;
    if (_stateBlurs && !oldBlurs) {
      _ensureRegistered();
    } else if (!_stateBlurs && oldBlurs) {
      _maybeUnregister();
    }
  }

  void _ensureRegistered() {
    if (_scope == null || _registered) return;
    _scope!.register(this);
    _registered = true;
    _onBudgetChanged = () {
      if (mounted) setState(() {});
    };
    _scope!.addListener(_onBudgetChanged!);
  }

  void _maybeUnregister() {
    if (!_registered) return;
    _scope!.removeListener(_onBudgetChanged!);
    _scope!.release(this);
    _registered = false;
    _onBudgetChanged = null;
  }

  @override
  void dispose() {
    _maybeUnregister();
    super.dispose();
  }

  BzGlassQuality _resolvedQuality(BuildContext context) {
    // Accessibility always wins over an optional quality override: no
    // caller may force blur on high-contrast or reduced-motion devices.
    if (MediaQuery.of(context).disableAnimations ||
        MediaQuery.highContrastOf(context)) {
      return BzGlassQuality.solid;
    }
    return widget.quality ?? BzGlassQuality.full;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final recipe = _recipes[widget.state]!;
    final quality = _resolvedQuality(context);
    final blurBudgeted = recipe.sigma > 0 && quality != BzGlassQuality.solid;
    final granted = !blurBudgeted ||
        _scope == null ||
        _scope!.grantOf(this) < _scope!.widget.maxVisibleSurfaces;

    final radius = BorderRadius.circular(widget.radius);
    // Flutter cannot paint a rounded BoxDecoration with differently colored
    // border sides. Use a consistent hairline rim; the soft lift shadow
    // supplies depth without triggering paint exceptions on every glass
    // surface (including accessibility and budget-demoted states).
    const border = Border.fromBorderSide(
      BorderSide(color: BzGlassEdge.color, width: BzGlassEdge.width),
    );
    final tint = _tint(widget.state, dark);

    if (blurBudgeted && granted) {
      final frost = quality == BzGlassQuality.frost;
      final sigma = frost ? recipe.sigma * 1.25 : recipe.sigma;
      final saturation = frost ? 1.0 : recipe.saturation;
      final ImageFilter filter = saturation == 1.0
          ? ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.mirror,
            )
          : ImageFilter.compose(
              outer: ColorFilter.matrix(saturationMatrix(saturation)),
              inner: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.mirror,
              ),
            );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow:
              widget.shadow ? const [BzGlassShadows.glassSoft] : const <BoxShadow>[],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: filter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint,
                borderRadius: radius,
                border: border,
              ),
              child: widget.child,
            ),
          ),
        ),
      );
    }

    // Solid path: accessibility fallback, budget demotion, or the clear
    // state's tint-only contract.
    final collapsed = quality == BzGlassQuality.solid || !granted;
    final fill = collapsed
        ? (dark ? BzLiquidColorsDark.surface : BzLiquidColorsLight.surface)
        : tint;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: border,
      ),
      child: widget.child,
    );
  }
}

/// Tint alpha per state (§2.2): 72% at top, 88% scrolled, 55% overlay,
/// 10% clear.
Color _tint(BzGlassState state, bool dark) {
  final base = dark ? BzGlassBase.dark : BzGlassBase.light;
  final alpha = switch (state) {
    BzGlassState.pillAtTop => 0.72,
    BzGlassState.pillScrolled => 0.88,
    BzGlassState.mediaOverlay => 0.55,
    BzGlassState.clear => 0.10,
  };
  return base.withValues(alpha: alpha);
}

/// Luminance-driven content color for anything sitting on glass.
///
/// Glass shows whatever is behind it rather than the theme's surface, so
/// the usual on-surface greys have nothing dependable to sit against.
/// Pure black or white off the theme's surface luminance is the only tint
/// that holds against arbitrary artwork.
Color bzGlassContentColor(BuildContext context) {
  final surface = Theme.of(context).colorScheme.surface;
  return surface.computeLuminance() > 0.5
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

/// The saturate(n) boost as a 5x4 color matrix for [ColorFilter.matrix].
List<double> saturationMatrix(double saturation) {
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  final inv = 1.0 - saturation;
  return [
    inv * lumR + saturation, inv * lumG, inv * lumB, 0, 0, //
    inv * lumR, inv * lumG + saturation, inv * lumB, 0, 0,
    inv * lumR, inv * lumG, inv * lumB + saturation, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
