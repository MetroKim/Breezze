import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Video viewing is separate from native Breezze audio playback.
///
/// A YouTube ID is metadata, not an audio stream or download grant. The
/// official embedded YouTube player should be used where available, retaining
/// YouTube branding, ads, playback restrictions, and uploader settings.
class YoutubePlayerHandoff {
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isValidProviderTrackId(String id) =>
      _videoIdPattern.hasMatch(id);

  /// The pinned IFrame player uses a supported WebView only on these systems.
  /// Linux/Windows keep a user-initiated official YouTube fallback.
  static bool supportsEmbeddedPlayer({
    required TargetPlatform platform,
    bool isWeb = false,
  }) =>
      isWeb ||
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;

  static Uri officialMusicUri(String providerTrackId) {
    if (!isValidProviderTrackId(providerTrackId)) {
      throw ArgumentError.value(
        providerTrackId, 'providerTrackId', 'Invalid YouTube Music video ID',
      );
    }
    return Uri.https('music.youtube.com', '/watch', {'v': providerTrackId});
  }

  /// Explicit handoff to the official YouTube Music app/site for provider
  /// features such as account entitlements and allowed offline playback.
  /// Nothing is downloaded, embedded, or played via Breezze's native engine.
  static Future<bool> openInYouTubeMusic(String providerTrackId) =>
      launchUrl(officialMusicUri(providerTrackId),
        mode: LaunchMode.externalApplication);

  static Future<bool> openProviderTrackId(String providerTrackId) async {
    if (!isValidProviderTrackId(providerTrackId)) {
      throw ArgumentError.value(
        providerTrackId, 'providerTrackId', 'Invalid YouTube video ID',
      );
    }
    final uri = Uri.https('www.youtube.com', '/watch', {'v': providerTrackId});
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
