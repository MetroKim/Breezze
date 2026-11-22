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

/// Offline media requires an explicit download grant. Generic catalogue
/// metadata (including Jamendo) cannot be downloaded by a discovery URL.
bool canRequestOfflineDownload(String id) =>
    id.trim().isNotEmpty &&
    !id.startsWith('bz:') &&
    !id.startsWith('bzv:');
