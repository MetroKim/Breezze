import 'package:url_launcher/url_launcher.dart';

/// Official Spotify app/web handoff.
///
/// A Spotify URI is not a media URL. Only the Spotify application/service is
/// allowed to obtain and decode the recording. Never pass a Spotify URI to
/// just_audio, audio_service, Cloudflare R2, or offline downloads.
class SpotifyPlaybackHandoff {
  static final RegExp _trackId = RegExp(r'^[A-Za-z0-9]{22}$');
  static final RegExp _breezzeId = RegExp(r'^bz:spotify:([A-Za-z0-9]{22})$');

  static bool isTrackId(String id) => _trackId.hasMatch(id);

  static String? spotifyIdFromBreezze(String id) =>
      _breezzeId.firstMatch(id)?.group(1);

  static Uri trackUrl(String id) {
    if (!isTrackId(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid Spotify track ID');
    }
    return Uri.https('open.spotify.com', '/track/$id');
  }

  static Uri searchUrl(String query) {
    final q = query.trim();
    if (q.isEmpty || q.length > 120) {
      throw ArgumentError.value(query, 'query', 'Invalid Spotify search');
    }
    return Uri.https('open.spotify.com', '/search/$q');
  }

  /// Spotify's installed app can take this HTTPS universal/app link.
  /// If unavailable, the official Spotify website handles the request.
  /// Opening a URI does not prove a Premium playback session has started.
  static Future<bool> openTrack(String spotifyTrackId) =>
      launchUrl(trackUrl(spotifyTrackId), mode: LaunchMode.externalApplication);

  static Future<bool> openSearch(String query) =>
      launchUrl(searchUrl(query), mode: LaunchMode.externalApplication);
}
