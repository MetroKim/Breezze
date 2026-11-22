/// Liquid Glass material contract (Apple Music spec, section 2.2).
///
/// Glass is a named material with a behavioral contract, not a generic
/// transparency value. The maximum visible blurred surfaces at any time
/// is 2; bar-spawned surfaces are blur-free near-opaque solids.
enum BzGlassState {
  /// Text-bearing top bar resting over a calm hero zone.
  /// 70-80 percent opacity; no busy imagery beneath text.
  pillAtTop,

  /// Default chrome once content can scroll beneath.
  /// 85-95 percent near-opaque surface plus blur 12-16px.
  pillScrolled,

  /// Media controls where the image remains the subject.
  /// Overlay chrome only; avoid dense text.
  mediaOverlay,

  /// Sparse, large controls over rich media only.
  /// No blur backing; tint/border only.
  clear,
}

/// The material recipe for each glass state. Implementations must use
/// exactly these values; deviating blurs or opacities break the contract.
class BzGlassMaterial {
  final double fillOpacity;
  final double blurSigma;
  final double saturation;
  final bool hasBlurBacking;

  const BzGlassMaterial({
    required this.fillOpacity,
    required this.blurSigma,
    required this.saturation,
    required this.hasBlurBacking,
  });

  /// pill-at-top: 70-80 percent opacity, no hard contrast beneath text.
  static const pillAtTop = BzGlassMaterial(
    fillOpacity: 0.75,
    blurSigma: 12,
    saturation: 1.8,
    hasBlurBacking: true,
  );

  /// pill-scrolled: 85-95 percent near-opaque + blur 12-16px.
  /// The saturate(180 percent) boost and blur(16px) are not optional.
  static const pillScrolled = BzGlassMaterial(
    fillOpacity: 0.88,
    blurSigma: 16,
    saturation: 1.8,
    hasBlurBacking: true,
  );

  /// media-overlay: media controls; image remains the subject.
  static const mediaOverlay = BzGlassMaterial(
    fillOpacity: 0.55,
    blurSigma: 18,
    saturation: 1.6,
    hasBlurBacking: true,
  );

  /// clear: sparse large controls over rich media; no blur backing.
  static const clear = BzGlassMaterial(
    fillOpacity: 0.12,
    blurSigma: 0,
    saturation: 1.0,
    hasBlurBacking: false,
  );

  BzGlassMaterial forState(BzGlassState state) {
    switch (state) {
      case BzGlassState.pillAtTop:
        return pillAtTop;
      case BzGlassState.pillScrolled:
        return pillScrolled;
      case BzGlassState.mediaOverlay:
        return mediaOverlay;
      case BzGlassState.clear:
        return clear;
    }
  }
}
