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
