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

class _FailingBridge implements BackgroundAudioBridge {
  int attempts = 0;

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
    attempts++;
    throw StateError('Simulated disappearing MPRIS/SMTC service');
  }
}

void main() {
  test('lost OS session falls back to no-op without crashing playback',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(backgroundSyncProvider);

    final failing = _FailingBridge();
    container.read(backgroundSessionAvailabilityProvider.notifier).state =
        BackgroundSessionAvailability.active;
    container.read(backgroundBridgeProvider.notifier).state = failing;

    // The failed Future is caught asynchronously, not thrown from a state
    // listener or propagated to the app's single PlayerController.
    await Future<void>.delayed(Duration.zero);

    expect(failing.attempts, greaterThan(0));
    expect(container.read(backgroundBridgeProvider),
        isA<NoopBackgroundBridge>());
    expect(container.read(backgroundSessionAvailabilityProvider),
        BackgroundSessionAvailability.unavailable);
  });


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
