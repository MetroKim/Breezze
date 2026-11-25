/// Explicit, foreground-only YouTube iframe watch queues.
///
/// These entries are provider video references, NEVER native audio sources,
/// downloadable assets, or playback rights. The official visible YouTube
/// player owns all media requests and its own restrictions.
class YoutubeVisibleQueue {
  static final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Preserve a supplied album/playlist order, deduplicate video IDs, and
  /// guarantee the selected song is represented in the queue.
  static List<Map<String, String?>> prepare({
    required String selectedVideoId,
    required String selectedTitle,
    required String selectedArtist,
    String? selectedArtworkUrl,
    Iterable<Map<String, String?>> entries = const [],
  }) {
    if (!_videoId.hasMatch(selectedVideoId)) return const [];
    final result = <Map<String, String?>>[];
    final seen = <String>{};
    for (final entry in entries) {
      final id = entry['videoId'];
      final title = entry['title'];
      if (id == null || !_videoId.hasMatch(id) ||
          title == null || title.trim().isEmpty ||
          !seen.add(id)) continue;
      result.add(Map<String, String?>.unmodifiable({
        'videoId': id,
        'title': title,
        'artist': entry['artist']?.trim().isNotEmpty == true
            ? entry['artist'] : 'YouTube Music',
        'artworkUrl': entry['artworkUrl'],
      }));
    }
    if (!seen.contains(selectedVideoId)) {
      result.insert(0, Map<String, String?>.unmodifiable({
        'videoId': selectedVideoId,
        'title': selectedTitle,
        'artist': selectedArtist,
        'artworkUrl': selectedArtworkUrl,
      }));
    }
    return List<Map<String, String?>>.unmodifiable(result);
  }

  /// Advance only after a video ends while its official iframe is on screen.
  /// Never schedule background playback or wrap to the first track.
  static int? nextAfterEnded({
    required int position,
    required int length,
    required bool foreground,
    required bool routeVisible,
  }) {
    if (!foreground || !routeVisible || position < 0 ||
        position + 1 >= length) return null;
    return position + 1;
  }
}
