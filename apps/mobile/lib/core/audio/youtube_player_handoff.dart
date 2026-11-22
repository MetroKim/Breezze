import 'package:url_launcher/url_launcher.dart';

/// Opens a dedicated music-video result in YouTube's official player.
///
/// This helper is for video viewing only. Song metadata from ytmusicapi must
/// never be passed to Breezze's native audio queue or treated as a stream URL.
class YoutubePlayerHandoff {
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{6,64}$');

  static Future<bool> openProviderTrackId(String providerTrackId) async {
    if (!_videoIdPattern.hasMatch(providerTrackId)) {
      throw ArgumentError.value(providerTrackId, 'providerTrackId', 'Invalid YouTube video ID');
    }
    final uri = Uri.https('www.youtube.com', '/watch', {'v': providerTrackId});
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
