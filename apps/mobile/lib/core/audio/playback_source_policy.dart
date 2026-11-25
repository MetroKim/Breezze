/// Spotify is the music playback provider; Deezer is legacy catalog metadata.
/// YouTube is strictly for visible video playback. Provider IDs must never
/// be mistaken for licensed, downloadable media URLs.
final _spotifyTrackId = RegExp(r'^bz:spotify:[A-Za-z0-9]{22}$');
final _deezerTrackId = RegExp(r'^bz:deezer:[0-9]{1,20}
final _deezerPreviewId = RegExp(r'^bz:deezer_preview:[0-9]{1,20}$');
final _youtubeSongId = RegExp(r'^bz:youtube_music:[A-Za-z0-9_-]{11}$');
final _youtubeVideoId = RegExp(r'^bzv:[A-Za-z0-9_-]{11}$');

bool isSpotifyTrackId(String id) => _spotifyTrackId.hasMatch(id);
bool isDeezerTrackId(String id) => _deezerTrackId.hasMatch(id);
bool isMusicBrainzTrackId(String id) => _musicBrainzId.hasMatch(id);
bool isDeezerPreview(String id) => _deezerPreviewId.hasMatch(id);
bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);

/// Spotify/Deezer *full* tracks must be handled by their official apps.
/// Deezer 30-second previews are a separate, explicitly requested native
/// audio action. Other external provider IDs and all videos are metadata.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    id.startsWith('bz:');

bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty &&
    !isYouTubeSongId(id) &&
    !isMetadataOnlyTrackId(id);

/// An available action may mean "open Spotify or official YouTube"; it does not
/// imply that Breezze can play, cache, redistribute or download full audio.
bool canOfferPlaybackAction(String id, {bool hasPreview = false}) =>
    // External catalogs cannot start a full song in Breezze without a
    // separately authorized, in-app playback source.
    isDeezerPreview(id) ||
    isYouTubeSongId(id) ||
    _youtubeVideoId.hasMatch(id) ||
    canQueueTrackId(id);

/// This only allows asking the server for its own licensed offline grant.
/// Every provider ID (including Deezer preview and Spotify) is blocked.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');

/// Legacy Deezer metadata matcher, retained for migration of saved items.
/// It does not authorize playback or upgrade a preview into a full song.
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
        isDeezerPreview(
            'bz:deezer_preview:' + row['providerTrackId'].toString());
  }).map((row) => row['providerTrackId'].toString()).toSet();

  return candidates.length == 1 ? candidates.first : null;
}
);
final _musicBrainzId = RegExp(r'^bz:musicbrainz:[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}
final _deezerPreviewId = RegExp(r'^bz:deezer_preview:[0-9]{1,20}$');
final _youtubeSongId = RegExp(r'^bz:youtube_music:[A-Za-z0-9_-]{11}$');
final _youtubeVideoId = RegExp(r'^bzv:[A-Za-z0-9_-]{11}$');

bool isSpotifyTrackId(String id) => _spotifyTrackId.hasMatch(id);
bool isDeezerTrackId(String id) => _deezerTrackId.hasMatch(id);
bool isDeezerPreview(String id) => _deezerPreviewId.hasMatch(id);
bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);

/// Spotify/Deezer *full* tracks must be handled by their official apps.
/// Deezer 30-second previews are a separate, explicitly requested native
/// audio action. Other external provider IDs and all videos are metadata.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    id.startsWith('bz:');

bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty &&
    !isYouTubeSongId(id) &&
    !isMetadataOnlyTrackId(id);

/// An available action may mean "open Spotify or official YouTube"; it does not
/// imply that Breezze can play, cache, redistribute or download full audio.
bool canOfferPlaybackAction(String id, {bool hasPreview = false}) =>
    // External catalogs cannot start a full song in Breezze without a
    // separately authorized, in-app playback source.
    isDeezerPreview(id) ||
    isYouTubeSongId(id) ||
    _youtubeVideoId.hasMatch(id) ||
    canQueueTrackId(id);

/// This only allows asking the server for its own licensed offline grant.
/// Every provider ID (including Deezer preview and Spotify) is blocked.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');

/// Legacy Deezer metadata matcher, retained for migration of saved items.
/// It does not authorize playback or upgrade a preview into a full song.
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
        isDeezerPreview(
            'bz:deezer_preview:' + row['providerTrackId'].toString());
  }).map((row) => row['providerTrackId'].toString()).toSet();

  return candidates.length == 1 ? candidates.first : null;
}
);
final _deezerPreviewId = RegExp(r'^bz:deezer_preview:[0-9]{1,20}$');
final _youtubeSongId = RegExp(r'^bz:youtube_music:[A-Za-z0-9_-]{11}$');
final _youtubeVideoId = RegExp(r'^bzv:[A-Za-z0-9_-]{11}$');

bool isSpotifyTrackId(String id) => _spotifyTrackId.hasMatch(id);
bool isDeezerTrackId(String id) => _deezerTrackId.hasMatch(id);
bool isDeezerPreview(String id) => _deezerPreviewId.hasMatch(id);
bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);

/// Spotify/Deezer *full* tracks must be handled by their official apps.
/// Deezer 30-second previews are a separate, explicitly requested native
/// audio action. Other external provider IDs and all videos are metadata.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    id.startsWith('bz:');

bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty &&
    !isYouTubeSongId(id) &&
    !isMetadataOnlyTrackId(id);

/// An available action may mean "open Spotify or official YouTube"; it does not
/// imply that Breezze can play, cache, redistribute or download full audio.
bool canOfferPlaybackAction(String id, {bool hasPreview = false}) =>
    // External catalogs cannot start a full song in Breezze without a
    // separately authorized, in-app playback source.
    isDeezerPreview(id) ||
    isYouTubeSongId(id) ||
    _youtubeVideoId.hasMatch(id) ||
    canQueueTrackId(id);

/// This only allows asking the server for its own licensed offline grant.
/// Every provider ID (including Deezer preview and Spotify) is blocked.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');

/// Legacy Deezer metadata matcher, retained for migration of saved items.
/// It does not authorize playback or upgrade a preview into a full song.
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
        isDeezerPreview(
            'bz:deezer_preview:' + row['providerTrackId'].toString());
  }).map((row) => row['providerTrackId'].toString()).toSet();

  return candidates.length == 1 ? candidates.first : null;
}
