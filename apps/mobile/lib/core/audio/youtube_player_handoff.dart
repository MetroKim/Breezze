import 'package:url_launcher/url_launcher.dart';

/// Opens YouTube-sourced music in YouTube's official player.
///
/// This is deliberately an external-player handoff: Breezze does not extract,
/// proxy, cache, or expose YouTube media stream URLs. The official player
/// controls playback, ads, account requirements, and platform capabilities.
class YoutubePlayerHandoff {
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{6,64}$');

  static Future<bool> openBreezzeTrackId(String breezzeTrackId) {
    if (!breezzeTrackId.startsWith('bz:')) {
      throw ArgumentError.value(
        breezzeTrackId,
        'breezzeTrackId',
        'Expected a YouTube Music-backed Breezze track ID',
      );
    }
    return openProviderTrackId(breezzeTrackId.substring(3));
  }

  static Future<bool> openProviderTrackId(String providerTrackId) async {
    if (!_videoIdPattern.hasMatch(providerTrackId)) {
      throw ArgumentError.value(providerTrackId, 'providerTrackId', 'Invalid YouTube video ID');
    }
    final uri = Uri.https('www.youtube.com', '/watch', {'v': providerTrackId});
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
