import 'package:audio_service/audio_service.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_controller.dart';

/// Native background-audio bridge over audio_service.
///
/// Lock-screen/notification media controls dispatch commands straight to
/// the global PlayerController — the controller stays the single
/// playback authority (§53.1); this handler is only the OS surface.
class AudioServiceBridge extends BaseAudioHandler implements Bridge {
  final Ref ref;

  AudioServiceBridge(this.ref);

  PlayerController get _player =>
      ref.read(playerControllerProvider.notifier);

  // ---- Lock-screen commands → PlayerController ---------------------

  @override
  Future<void> play() => _player.togglePlayPause();

  @override
  Future<void> pause() => _player.togglePlayPause();

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> seek(Duration position) => _player.seekTo(position);

  @override
  Future<void> stop() async {
    await super.stop();
    await super.onStop();
  }
}

/// The small interface background_audio.dart's sync expects.
abstract interface class Bridge {
  Future<void> play();
  Future<void> pause();
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> seek(Duration position);
  Future<void> stop();
}

/// Starts audio_service with our handler; call once from bootstrap
/// before the first frame (needs a WidgetsBinding provider container).
Future<void> startBackgroundAudio(ProviderContainer container) async {
  await AudioService.init(
    builder: () => AudioServiceBridge(container as dynamic),
    config: const AudioServiceConfig(
      androidNotificationChannelName: 'Breezze playback',
      androidNotificationChannelDescription:
          'Playback controls for Breezze',
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Pushes player state to the OS media session.
void syncMediaSession(
  BaseAudioHandler handler, {
  required String title,
  required String artist,
  String? artworkUrl,
  required bool playing,
  required Duration position,
  required Duration duration,
}) {
  handler.playbackState.add(PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ],
    systemActions: const {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    },
    androidCompactActionIndices: const [0, 1, 2],
    processingState: playing
        ? AudioProcessingState.ready
        : AudioProcessingState.idle,
    playing: playing,
    updatePosition: position,
    bufferedPosition: position,
    speed: 1.0,
  ));

  final item = MediaItem(
    id: 'current',
    title: title,
    artist: artist,
    duration: duration,
    artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
  );
  handler.mediaItem.add(item);
}
