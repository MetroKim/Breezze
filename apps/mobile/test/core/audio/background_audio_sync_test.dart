import 'package:breezze/core/audio/background_audio.dart';
import 'package:breezze/core/audio/audio_service_bridge.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
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
  test('single OS media bridge is eligible on each native desktop/mobile', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(supportsBreezzeSystemMediaSession(platform), isTrue);
      expect(supportsBreezzeSystemMediaSession(platform, isWeb: true), isFalse);
    }
    expect(supportsBreezzeSystemMediaSession(TargetPlatform.fuchsia), isFalse);
  });

  test('native bridge swap immediately publishes the current media state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(backgroundSyncProvider);

    final bridge = _RecordingBridge();
    container.read(backgroundBridgeProvider.notifier).state = bridge;

    expect(bridge.updates, 1);
  });
}
