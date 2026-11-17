import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/player/player_controller.dart';

/// Background-audio state this handler mirrors from PlayerController.
///
/// The PlayerController stays the single playback authority (§53.1);
/// this handler only bridges it to the OS: notification, lock-screen
/// controls, audio focus. Commands arrive from the lock screen as
/// callbacks and are dispatched straight to the controller.
abstract class BackgroundAudioBridge {
  /// Starts the OS media session; call once at startup.
  Future<void> start();

  /// Pushes the current state to the OS (notification + lock screen).
  Future<void> update({
    required String title,
    required String artist,
    String? artworkUrl,
    required bool playing,
  });

  /// Stops the OS media session.
  Future<void> stop();
}

/// A no-op bridge for platforms/desktop until native wiring runs.
class NoopBackgroundBridge implements BackgroundAudioBridge {
  @override
  Future<void> start() async {}

  @override
  Future<void> update({
    required String title,
    required String artist,
    String? artworkUrl,
    required bool playing,
  }) async {}

  @override
  Future<void> stop() async {}
}

/// Keeps the OS media session in sync with the player state — one
/// subscription, app-wide.
class BackgroundAudioSync {
  final BackgroundAudioBridge bridge;
  final Ref ref;
  Function()? _unwatch;

  BackgroundAudioSync({required this.bridge, required this.ref});

  void start() {
    _unwatch = ref.listen(playerControllerProvider, (prev, next) {
      final track = next.currentTrack;
      if (next.playbackState == PlaybackState.idle) {
        bridge.stop();
        return;
      }
      if (track == null) return;
      bridge.update(
        title: track.title ?? 'Unknown track',
        artist: track.artist ?? '',
        artworkUrl: track.artworkUrl,
        playing: next.playbackState == PlaybackState.playing,
      );
    }, fireImmediately: false);
  }

  void dispose() {
    _unwatch?.call();
    bridge.stop();
  }
}

/// The bridge provider — overridden with a native implementation
/// (audio_service) on Android/iOS in main bootstrap.
final backgroundBridgeProvider =
    Provider<BackgroundAudioBridge>((ref) => NoopBackgroundBridge());

/// The sync wrapper, started once at app start.
final backgroundSyncProvider = Provider<BackgroundAudioSync>((ref) {
  final sync = BackgroundAudioSync(
    bridge: ref.watch(backgroundBridgeProvider),
    ref: ref,
  );
  ref.onDispose(sync.dispose);
  sync.start();
  return sync;
});
