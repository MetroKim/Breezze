import 'package:url_launcher/url_launcher.dart';

/// Official Deezer playback handoff. A Deezer catalog track ID is never
/// a raw full-song URL for just_audio. Full playback belongs to Deezer.
class DeezerPlaybackHandoff {
  static final RegExp _id = RegExp(r'^[0-9]{1,20}$');
  static final RegExp _breezzeId =
      RegExp(r'^bz:deezer(?:_preview)?:([0-9]{1,20})$');

  static bool isTrackId(String id) => _id.hasMatch(id);

  static String? deezerIdFromBreezze(String id) =>
      _breezzeId.firstMatch(id)?.group(1);

  static Uri trackUrl(String id) {
    if (!isTrackId(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid Deezer track ID');
    }
    return Uri.https('www.deezer.com', '/track/$id');
  }

  static Uri searchUrl(String query) {
    final text = query.trim();
    if (text.isEmpty || text.length > 120) {
      throw ArgumentError.value(query, 'query', 'Invalid Deezer search query');
    }
    return Uri.https('www.deezer.com', '/search/$text');
  }

  /// Launching Deezer's application or web player does not assert playback
  /// entitlement. Deezer manages full-track licensing and account access.
  static Future<bool> openTrack(String id) =>
      launchUrl(trackUrl(id), mode: LaunchMode.externalApplication);

  static Future<bool> openSearch(String query) =>
      launchUrl(searchUrl(query), mode: LaunchMode.externalApplication);
}
