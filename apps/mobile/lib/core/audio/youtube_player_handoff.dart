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
