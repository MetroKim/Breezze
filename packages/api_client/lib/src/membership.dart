/// Breezze premium/entitlement domain — spec §18, §58.2.
///
/// Client-side flags are presentation hints only; the server is the
/// entitlement authority (§18.4). Real plans/prices must be configured
/// per business model and territories (§58.1) — never hard-coded.
enum MembershipTier { free, premium, family, student }

/// Audio settings block — mirrors the parent apps' quality settings.
class AudioSettings {
  /// Streaming quality tier (§19.2).
  final String streamingQuality;

  /// Download quality tier (§19.4).
  final String downloadQuality;

  /// Wi-Fi-only downloads default (§19.4).
  final bool downloadWifiOnly;

  /// Crossfade duration 0–12 s (§9.7).
  final Duration crossfade;

  /// Gapless playback on/off.
  final bool gapless;

  /// AutoMix DJ transitions (premium).
  final bool automix;

  /// Lossless streaming (premium-gated server-side; hint only).
  final bool losslessEnabled;

  /// Hi-Res Lossless (premium-gated server-side; hint only).
  final bool hiResEnabled;

  /// Audio normalization / Sound Check (§9.8).
  final bool soundCheck;

  const AudioSettings({
    this.streamingQuality = 'high',
    this.downloadQuality = 'lossless',
    this.downloadWifiOnly = true,
    this.crossfade = Duration.zero,
    this.gapless = true,
    this.automix = false,
    this.losslessEnabled = false,
    this.hiResEnabled = false,
    this.soundCheck = false,
  });

  AudioSettings copyWith({
    String? streamingQuality,
    String? downloadQuality,
    bool? downloadWifiOnly,
    Duration? crossfade,
    bool? gapless,
    bool? automix,
    bool? losslessEnabled,
    bool? hiResEnabled,
    bool? soundCheck,
  }) =>
      AudioSettings(
        streamingQuality: streamingQuality ?? this.streamingQuality,
        downloadQuality: downloadQuality ?? this.downloadQuality,
        downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
        crossfade: crossfade ?? this.crossfade,
        gapless: gapless ?? this.gapless,
        automix: automix ?? this.automix,
        losslessEnabled: losslessEnabled ?? this.losslessEnabled,
        hiResEnabled: hiResEnabled ?? this.hiResEnabled,
        soundCheck: soundCheck ?? this.soundCheck,
      );
}

/// Server-issued entitlement snapshot (§18.4). Client consumes, never decides.
class Entitlement {
  final MembershipTier tier;
  final bool canStreamLossless;
  final bool canStreamHiRes;
  final bool canDownload;
  final bool canUseAutomix;
  final bool active;

  const Entitlement({
    required this.tier,
    required this.canStreamLossless,
    required this.canStreamHiRes,
    required this.canDownload,
    required this.canUseAutomix,
    required this.active,
  });

  static const free = Entitlement(
    tier: MembershipTier.free,
    canStreamLossless: false,
    canStreamHiRes: false,
    canDownload: false,
    canUseAutomix: false,
    active: true,
  );

  static const premium = Entitlement(
    tier: MembershipTier.premium,
    canStreamLossless: true,
    canStreamHiRes: true,
    canDownload: true,
    canUseAutomix: true,
    active: true,
  );
}
