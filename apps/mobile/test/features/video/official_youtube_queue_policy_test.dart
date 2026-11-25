import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/features/video/official_youtube_queue_policy.dart';

void main() {
  test('saved YouTube queue preserves song order and selected index', () {
    const a = OfficialYouTubeQueueEntry(
      videoId: 'dQw4w9WgXcQ', title: 'First', artist: 'Artist');
    const b = OfficialYouTubeQueueEntry(
      videoId: 'abcdefghijk', title: 'Second', artist: 'Artist');
    const invalid = OfficialYouTubeQueueEntry(
      videoId: 'invalid', title: 'Bad', artist: 'Unknown');
    final result = normalizedOfficialYouTubeQueue(
      [a, invalid, b, a], selectedVideoId: b.videoId);
    expect(result.map((e) => e.videoId).toList(), [a.videoId, b.videoId]);
    expect(result.indexWhere((e) => e.videoId == b.videoId), 1);
  });

  test('rejects an unrelated playlist that lacks the opened recording', () {
    final result = normalizedOfficialYouTubeQueue(
      [const OfficialYouTubeQueueEntry(
        videoId: 'dQw4w9WgXcQ', title: 'First', artist: 'Artist')],
      selectedVideoId: 'abcdefghijk');
    expect(result, isEmpty);
  });

  const videoId = 'dQw4w9WgXcQ';

  test('advances a completed visible official YouTube queue item', () {
    expect(nextForegroundYouTubeQueueIndex(
      videoEnded: true,
      playerVisible: true,
      currentVideoId: videoId,
      reportedVideoId: videoId,
      currentIndex: 0,
      queueLength: 3,
    ), 1);
  });

  test('stops at last item instead of looping', () {
    expect(nextForegroundYouTubeQueueIndex(
      videoEnded: true,
      playerVisible: true,
      currentVideoId: videoId,
      reportedVideoId: videoId,
      currentIndex: 2,
      queueLength: 3,
    ), isNull);
  });

  test('never advances hidden, unfinished or stale video events', () {
    for (final policy in [
      (ended: false, visible: true, id: videoId),
      (ended: true, visible: false, id: videoId),
      (ended: true, visible: true, id: 'abcdefghijk'),
      (ended: true, visible: true, id: ''),
    ]) {
      expect(nextForegroundYouTubeQueueIndex(
        videoEnded: policy.ended,
        playerVisible: policy.visible,
        currentVideoId: videoId,
        reportedVideoId: policy.id,
        currentIndex: 0,
        queueLength: 3,
      ), isNull);
    }
  });

  test('rejects invalid indexes and empty queues', () {
    for (final index in [-1, 0, 1]) {
      expect(nextForegroundYouTubeQueueIndex(
        videoEnded: true,
        playerVisible: true,
        currentVideoId: videoId,
        reportedVideoId: videoId,
        currentIndex: index,
        queueLength: 0,
      ), isNull);
    }
  });
}
