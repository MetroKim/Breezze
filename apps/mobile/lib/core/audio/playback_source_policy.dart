/// Provider IDs must not be confused with playable media grants.
///
/// YouTube IDs launch only visible video. Spotify IDs launch only official
/// Spotify playback. Neither supplies Breezze with a native stream or download.
final _deezerPreview = RegExp(r'^bz:deezer_preview:[0-9]{1,20}$');
final _youtubeSongId = RegExp(r'^bz:youtube_music:[A-Za-z0-9_-]{11}$');
final _youtubeVideoId = RegExp(r'^bzv:[A-Za-z0-9_-]{11}
final _deezerCatalogId = RegExp(r'^bz:deezer:[0-9]{1,20}$');

bool isDeezerPreview(String id) => _deezerPreview.hasMatch(id);
bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);
bool isSpotifyTrackId(String id) => _spotifyTrackId.hasMatch(id);

/// A queued song must still resolve to a playable, permitted media source.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    id.startsWith('bz:');

/// Native audio playback is separate from the visible YouTube player.
bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty &&
    !isYouTubeSongId(id) &&
    !isMetadataOnlyTrackId(id);

/// Search and playlist results can offer official YouTube video playback
/// without incorrectly granting native audio or offline capabilities.
bool canOfferPlaybackAction(String id, {bool hasPreview = false}) =>
    isYouTubeSongId(id) ||
    isSpotifyTrackId(id) ||
    _youtubeVideoId.hasMatch(id) ||
    canQueueTrackId(id);

/// Only permits REQUESTING a server-side offline grant, not downloading it.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');

/// Legacy Deezer preview-matching helper retained only for migration of
/// previously saved metadata; never used to start new playback.
/// Preview fallback must refer unambiguously to the selected recording.
String? matchingDeezerPreview(
  Object? rows,
  String title,
  String artist,
  Duration duration,
) {
  if (rows is! List) return null;
  String normalize(String value) => value.trim().toLowerCase();

  final candidates = rows.whereType<Map>().where((row) {
    final seconds = row['durationSec'];
    return row['title'] is String &&
        normalize(row['title'] as String) == normalize(title) &&
        row['artist'] is String &&
        normalize(row['artist'] as String) == normalize(artist) &&
        (duration == Duration.zero ||
            (seconds is num &&
                (seconds - duration.inSeconds).abs() <= 3)) &&
        row['previewUrl'] is String &&
        isDeezerPreview('bz:deezer_preview:' + row['providerTrackId'].toString());
  }).map((row) => row['providerTrackId'].toString()).toSet();

  return candidates.length == 1 ? candidates.first : null;
}
);
final _spotifyTrackId = RegExp(r'^bz:spotify:[A-Za-z0-9]{22}
final _deezerCatalogId = RegExp(r'^bz:deezer:[0-9]{1,20}$');

bool isDeezerPreview(String id) => _deezerPreview.hasMatch(id);
bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);

/// A queued song must still resolve to a playable, permitted media source.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    (id.startsWith('bz:') && !isYouTubeSongId(id) && !isDeezerPreview(id));

/// Native audio playback is separate from the visible YouTube player.
bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty &&
    !isYouTubeSongId(id) &&
    !isMetadataOnlyTrackId(id);

/// Search and playlist results can offer official YouTube video playback
/// without incorrectly granting native audio or offline capabilities.
bool canOfferPlaybackAction(String id, {bool hasPreview = false}) =>
    isYouTubeSongId(id) ||
    _youtubeVideoId.hasMatch(id) ||
    (hasPreview && _deezerCatalogId.hasMatch(id)) ||
    canQueueTrackId(id);

/// Only permits REQUESTING a server-side offline grant, not downloading it.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');

/// Preview fallback must refer unambiguously to the selected recording.
String? matchingDeezerPreview(
  Object? rows,
  String title,
  String artist,
  Duration duration,
) {
  if (rows is! List) return null;
  String normalize(String value) => value.trim().toLowerCase();

  final candidates = rows.whereType<Map>().where((row) {
    final seconds = row['durationSec'];
    return row['title'] is String &&
        normalize(row['title'] as String) == normalize(title) &&
        row['artist'] is String &&
        normalize(row['artist'] as String) == normalize(artist) &&
        (duration == Duration.zero ||
            (seconds is num &&
                (seconds - duration.inSeconds).abs() <= 3)) &&
        row['previewUrl'] is String &&
        isDeezerPreview('bz:deezer_preview:' + row['providerTrackId'].toString());
  }).map((row) => row['providerTrackId'].toString()).toSet();

  return candidates.length == 1 ? candidates.first : null;
}
);
final _deezerCatalogId = RegExp(r'^bz:deezer:[0-9]{1,20}$');

bool isDeezerPreview(String id) => _deezerPreview.hasMatch(id);
bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);

/// A queued song must still resolve to a playable, permitted media source.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    (id.startsWith('bz:') && !isYouTubeSongId(id) && !isDeezerPreview(id));

/// Native audio playback is separate from the visible YouTube player.
bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty &&
    !isYouTubeSongId(id) &&
    !isMetadataOnlyTrackId(id);

/// Search and playlist results can offer official YouTube video playback
/// without incorrectly granting native audio or offline capabilities.
bool canOfferPlaybackAction(String id, {bool hasPreview = false}) =>
    isYouTubeSongId(id) ||
    _youtubeVideoId.hasMatch(id) ||
    (hasPreview && _deezerCatalogId.hasMatch(id)) ||
    canQueueTrackId(id);

/// Only permits REQUESTING a server-side offline grant, not downloading it.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');

/// Preview fallback must refer unambiguously to the selected recording.
String? matchingDeezerPreview(
  Object? rows,
  String title,
  String artist,
  Duration duration,
) {
  if (rows is! List) return null;
  String normalize(String value) => value.trim().toLowerCase();

  final candidates = rows.whereType<Map>().where((row) {
    final seconds = row['durationSec'];
    return row['title'] is String &&
        normalize(row['title'] as String) == normalize(title) &&
        row['artist'] is String &&
        normalize(row['artist'] as String) == normalize(artist) &&
        (duration == Duration.zero ||
            (seconds is num &&
                (seconds - duration.inSeconds).abs() <= 3)) &&
        row['previewUrl'] is String &&
        isDeezerPreview('bz:deezer_preview:' + row['providerTrackId'].toString());
  }).map((row) => row['providerTrackId'].toString()).toSet();

  return candidates.length == 1 ? candidates.first : null;
}
