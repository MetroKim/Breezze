import 'package:url_launcher/url_launcher.dart';

import '../api/breezze_api.dart';

/// Opens YouTube-sourced music in YouTube's official player.
///
/// This is deliberately an external-player handoff: Breezze does not extract,
/// proxy, cache, or expose YouTube media stream URLs. The official player
/// controls playback, ads, account requirements, and platform capabilities.
class YoutubePlayerHandoff {
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{6,64}$');

  static Future<bool> openFromApi(BreezzeApi api, String breezzeTrackId) async {
    if (!breezzeTrackId.startsWith('bz:')) {
      throw ArgumentError.value(
        breezzeTrackId,
        'breezzeTrackId',
        'Expected a YouTube Music-backed Breezze track ID',
      );
    }
    final providerTrackId = breezzeTrackId.substring(3);
    final response = await api.getProviderPlaybackLaunch(
      'youtube_music',
      providerTrackId,
    );
    final descriptor = response['value'];
    if (response['kind'] != 'ok' || descriptor is! Map) {
      throw StateError('YouTube Music official-player handoff is unavailable');
    }
    final watchUrl = descriptor['watchUrl'];
    if (watchUrl is! String || watchUrl.isEmpty) {
      throw StateError('Provider returned no official YouTube watch URL');
    }
    return openBreezzeTrackId(breezzeTrackId, watchUrl: watchUrl);
  }

  static Future<bool> openBreezzeTrackId(String breezzeTrackId, {String? watchUrl}) {
    if (!breezzeTrackId.startsWith('bz:')) {
      throw ArgumentError.value(
        breezzeTrackId,
        'breezzeTrackId',
        'Expected a YouTube Music-backed Breezze track ID',
      );
    }
    return openProviderTrackId(breezzeTrackId.substring(3), watchUrl: watchUrl);
  }

  static Future<bool> openProviderTrackId(String providerTrackId, {String? watchUrl}) async {
    if (!_videoIdPattern.hasMatch(providerTrackId)) {
      throw ArgumentError.value(providerTrackId, 'providerTrackId', 'Invalid YouTube video ID');
    }
    final uri = watchUrl == null
        ? Uri.https('www.youtube.com', '/watch', {'v': providerTrackId})
        : Uri.tryParse(watchUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'www.youtube.com' ||
        uri.path != '/watch' ||
        uri.queryParameters['v'] != providerTrackId) {
      throw ArgumentError.value(watchUrl, 'watchUrl', 'Expected the matching official YouTube watch URL');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
