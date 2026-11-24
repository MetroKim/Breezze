import 'package:breezze/core/audio/background_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingBridge implements BackgroundAudioBridge {
  int updates = 0;

  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}

  @override
  Future<void> update({
    required String title,
    required String artist,
    String? artworkUrl,
    required bool playing,
  }) async {
    updates++;
  }
}

void main() {
  test('native bridge swap immediately publishes the current media state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(backgroundSyncProvider);

    final bridge = _RecordingBridge();
    container.read(backgroundBridgeProvider.notifier).state = bridge;

    expect(bridge.updates, 1);
  });
}
