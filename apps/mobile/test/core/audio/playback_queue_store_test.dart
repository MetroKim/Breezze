import 'package:breezze/core/audio/playback_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved playback queue data is isolated by account and can be cleared',
      () async {
    final values = <String, String>{};
    final store = PlaybackQueueStore(
      read: (key) async => values[key],
      write: (key, value) async {
        if (value == null) {
          values.remove(key);
        } else {
          values[key] = value;
        }
      },
    );
    final snapshot = <String, dynamic>{
      'v': 1,
      'selected': 'entry-one',
      'positionMs': 16000,
      'entries': <Map<String, dynamic>>[],
    };
    await store.save('user-a', snapshot);
    expect(await store.load('user-b'), isNull);
    expect(await store.load('user-a'), snapshot);

    await store.clear('user-a');
    expect(await store.load('user-a'), isNull);
    expect(values, isEmpty);
  });

  test('corrupt queue snapshot is ignored without exposing another owner', () async {
    final store = PlaybackQueueStore(
      read: (key) async => '{not-json',
      write: (key, value) async {},
    );
    expect(await store.load('user-a'), isNull);
    await expectLater(store.load('../user-b'), throwsArgumentError);
  });
}
