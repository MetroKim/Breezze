import 'package:breezze/features/video/youtube_visible_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('album order is preserved and the selected track is not moved', () {
    final queue = YoutubeVisibleQueue.prepare(
      selectedVideoId: 'bcdefghijkl',
      selectedTitle: 'Second song',
      selectedArtist: 'Artist',
      entries: const [
        {'videoId': 'abcdefghijk', 'title': 'First song', 'artist': 'Artist'},
        {'videoId': 'bcdefghijkl', 'title': 'Second song', 'artist': 'Artist'},
        {'videoId': 'cdefghijklm', 'title': 'Third song', 'artist': 'Artist'},
      ],
    );
    expect(queue.map((item) => item['videoId']).toList(), [
      'abcdefghijk', 'bcdefghijkl', 'cdefghijklm',
    ]);
  });

  test('bad IDs, empty titles and duplicate provider results are removed', () {
    final queue = YoutubeVisibleQueue.prepare(
      selectedVideoId: 'abcdefghijk',
      selectedTitle: 'Selected',
      selectedArtist: 'Artist',
      entries: const [
        {'videoId': 'invalid', 'title': 'Invalid video'},
        {'videoId': 'bcdefghijkl', 'title': '  '},
        {'videoId': 'cdefghijklm', 'title': 'Valid'},
        {'videoId': 'cdefghijklm', 'title': 'Duplicate'},
      ],
    );
    expect(queue.map((item) => item['videoId']).toList(),
      ['abcdefghijk', 'cdefghijklm']);
    expect(queue.first['title'], 'Selected');
    expect(() => queue.add({'videoId': 'defghijklmn'}),
      throwsUnsupportedError);
    expect(() => queue.first['title'] = 'Rewritten', throwsUnsupportedError);
  });

  test('an invalid selected provider ID never starts a queue', () {
    expect(YoutubeVisibleQueue.prepare(
      selectedVideoId: 'malformed',
      selectedTitle: 'Bad source',
      selectedArtist: 'Artist',
    ), isEmpty);
  });

  test('automatic next is foreground-only with no repeat at the end', () {
    expect(YoutubeVisibleQueue.nextAfterEnded(
      position: 1, length: 3, foreground: true, routeVisible: true), 2);
    expect(YoutubeVisibleQueue.nextAfterEnded(
      position: 2, length: 3, foreground: true, routeVisible: true), isNull);
    expect(YoutubeVisibleQueue.nextAfterEnded(
      position: 0, length: 3, foreground: false, routeVisible: true), isNull);
    expect(YoutubeVisibleQueue.nextAfterEnded(
      position: 0, length: 3, foreground: true, routeVisible: false), isNull);
    expect(YoutubeVisibleQueue.nextAfterEnded(
      position: -1, length: 3, foreground: true, routeVisible: true), isNull);
  });
}
