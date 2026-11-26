import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_controller.dart';

/// Background-audio bridge contract.
///
/// The PlayerController stays the single playback authority (§53.1);
/// the bridge only mirrors state to the OS (notification, lock-screen
/// controls) and forwards OS commands to the controller.
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

/// A no-op bridge for platforms without a media session (desktop, web,
/// or when audio_service is unavailable). Playback is unaffected.
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

/// The bridge provider — starts as the no-op; swapped for the native
/// audio_service bridge once it initializes.
final backgroundBridgeProvider =
    StateProvider<BackgroundAudioBridge>((ref) => NoopBackgroundBridge());

/// Visible, non-secret diagnostic for media controls. It reports whether
/// the OS bridge actually started, not whether the Dart package exists.
enum BackgroundSessionAvailability {
  initializing,
  active,
  unavailable,
  unsupported,
}

final backgroundSessionAvailabilityProvider =
    StateProvider<BackgroundSessionAvailability>(
        (ref) => BackgroundSessionAvailability.initializing);


/// Keeps the OS media session in sync with the player state — one
/// subscription, app-wide.
class BackgroundAudioSync {
  final Ref ref;
  ProviderSubscription<PlayerState>? _subscription;
  bool _disposed = false;

  BackgroundAudioSync({required this.ref});

  void _publish(
    BackgroundAudioBridge bridge, {
    required String title,
    required String artist,
    String? artworkUrl,
    required bool playing,
  }) {
    if (_disposed) return;
    // A desktop D-Bus/SMTC server may vanish *after* initialization. Future
    // failures must never escape an unawaited listener and crash playback.
    // The single controller remains authoritative; only its OS projection
    // becomes temporarily unavailable.
    unawaited(
      Future<void>.sync(() => bridge.update(
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        playing: playing,
      )).catchError((Object error, StackTrace stackTrace) {
        if (_disposed || ref.read(backgroundBridgeProvider) != bridge) return;
        ref.read(backgroundSessionAvailabilityProvider.notifier).state =
            BackgroundSessionAvailability.unavailable;
        ref.read(backgroundBridgeProvider.notifier).state =
            NoopBackgroundBridge();
      }),
    );
  }


  void start() {
    // Native media-session initialization can finish after the player has
    // already selected a song. Restart to republish current metadata now.
    _subscription?.close();
    _subscription = ref.listen(playerControllerProvider, (prev, next) {
      final track = next.currentTrack;
      final trackChanged = prev?.currentTrack?.id != track?.id;
      final playbackChanged = prev?.playbackState != next.playbackState;
      final queueChanged = prev?.queueVersion != next.queueVersion;
      final pausedSeekChanged = prev != null &&
          prev.position != next.position &&
          next.playbackState != PlaybackState.playing &&
          next.playbackState != PlaybackState.buffering &&
          next.playbackState != PlaybackState.loading &&
          next.playbackState != PlaybackState.resolving;
      // audio_service projects position from elapsed wall time. Do not publish
      // every player position tick; only send state/track/queue/seek changes.
      if (!trackChanged && !playbackChanged && !queueChanged && !pausedSeekChanged) {
        return;
      }
      final bridge = ref.read(backgroundBridgeProvider);
      if (next.playbackState == PlaybackState.idle || track == null) {
        // Clear OS metadata without invoking the handler's user-requested
        // stop action (which also stops the PlayerController).
        _publish(bridge, title: '', artist: '', playing: false);
        return;
      }
      _publish(
        bridge,
        title: track.title ?? 'Unknown track',
        artist: track.artist ?? '',
        artworkUrl: track.artworkUrl,
        playing: next.playbackState == PlaybackState.playing,
      );
    }, fireImmediately: true);
  }

  void dispose() {
    _disposed = true;
    _subscription?.close();
  }
}

/// The sync wrapper, started once at app start. Re-created if the bridge
/// swaps so the new bridge receives updates immediately.
final backgroundSyncProvider = Provider<BackgroundAudioSync>((ref) {
  final sync = BackgroundAudioSync(ref: ref);
  ref.listen(backgroundBridgeProvider, (_, __) {
    // Republish immediately when audio_service becomes available, including
    // when playback was already paused before native initialization.
    sync.start();
  });
  ref.onDispose(sync.dispose);
  sync.start();
  return sync;
});
