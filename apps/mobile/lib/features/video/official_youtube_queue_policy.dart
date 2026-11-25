/// Guards official YouTube foreground watch-queue transitions.
///
/// This does not authorize standalone audio streams, hidden playback or
/// downloads. The official visible iFrame retains control of playback.
int? nextForegroundYouTubeQueueIndex({
  required bool videoEnded,
  required bool playerVisible,
  required String currentVideoId,
  required String reportedVideoId,
  required int currentIndex,
  required int queueLength,
}) {
  if (!videoEnded ||
      !playerVisible ||
      currentVideoId.isEmpty ||
      reportedVideoId != currentVideoId ||
      currentIndex < 0 ||
      currentIndex + 1 >= queueLength) {
    return null;
  }
  return currentIndex + 1;
}

/// One item in a user-owned, visible official YouTube watch queue.
class OfficialYouTubeQueueEntry {
  final String videoId;
  final String title;
  final String artist;
  final String? artworkUrl;

  const OfficialYouTubeQueueEntry({
    required this.videoId,
    required this.title,
    required this.artist,
    this.artworkUrl,
  });
}

/// Uses only validated video IDs, keeps the user's order, and de-duplicates.
/// This metadata does not grant audio-only or offline playback.
List<OfficialYouTubeQueueEntry> normalizedOfficialYouTubeQueue(
  List<OfficialYouTubeQueueEntry> entries, {
  required String selectedVideoId,
}) {
  final validId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  final seen = <String>{};
  final normalized = <OfficialYouTubeQueueEntry>[];
  for (final item in entries) {
    if (!validId.hasMatch(item.videoId) || !seen.add(item.videoId)) continue;
    normalized.add(item);
    if (normalized.length == 25) break;
  }
  // A saved playlist is only a valid playback queue if it includes the
  // selected song. Callers can use ordinary discovery otherwise.
  if (!seen.contains(selectedVideoId)) return [];
  return normalized;
}
