final _deezerPreview = RegExp(r'^bz:deezer_preview:[0-9]{1,20}$');
bool isDeezerPreview(String id) => _deezerPreview.hasMatch(id);

final _youtubeSongId = RegExp(r'^bz:youtube_music:[A-Za-z0-9_-]{11}$');

bool isYouTubeSongId(String id) => _youtubeSongId.hasMatch(id);

/// A queued song still needs a source from the session resolver.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    (id.startsWith('bz:') && !id.startsWith('bz:jamendo:') && !isYouTubeSongId(id) && !isDeezerPreview(id));

bool canQueueTrackId(String id) => id.trim().isNotEmpty && !isMetadataOnlyTrackId(id);

/// Offline media requires an explicit download grant. Generic catalogue
/// metadata (including Jamendo) cannot be downloaded by a discovery URL.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');
