/// A catalogue match is not automatically an authorized playback source.
///
/// Provider metadata uses Breezze-scoped IDs. Only the approved Jamendo
/// provider may enter the native queue from that namespace; playback itself
/// still requires a successful backend rights/territory resolution.
///
/// Videos have a separate provider player and never enter the audio queue.
bool isMetadataOnlyTrackId(String id) =>
    id.startsWith('bzv:') ||
    (id.startsWith('bz:') && !id.startsWith('bz:jamendo:'));

bool canQueueTrackId(String id) =>
    id.trim().isNotEmpty && !isMetadataOnlyTrackId(id);

/// YouTube Music results may be opened in the visible official video player.
/// They remain separate from native audio queues and offline downloads.
String? youtubeEmbeddedVideoId(String id) {
  const prefix = 'bz:youtube_music:';
  if (!id.startsWith(prefix)) return null;
  final videoId = id.substring(prefix.length);
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) ? videoId : null;
}

/// Offline media requires an explicit download grant. Generic catalogue
/// metadata (including Jamendo) cannot be downloaded by a discovery URL.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');
