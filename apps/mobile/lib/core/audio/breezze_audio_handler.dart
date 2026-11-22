import 'package:audio_service/audio_service.dart' as audio;
import 'package:breezze_audio_contracts/audio_contracts.dart' as contracts;

import '../../features/player/player_controller.dart';

/// OS media-session bridge for Android/iOS lock-screen and headset controls.
///
/// This class does not own an audio player. All commands are delegated to
/// Breezze's single PlayerController, which remains the sole playback authority.
class BreezzeAudioHandler extends audio.BaseAudioHandler {
  BreezzeAudioHandler(this._controller);

  final PlayerController _controller;

  Future<void> play() => _controller.resume();

  Future<void> pause() => _controller.pause();

  Future<void> stop() async {
    await _controller.stop();
    await super.stop();
  }

  Future<void> seek(Duration position) => _controller.seekTo(position);

  Future<void> skipToNext() => _controller.next();

  Future<void> skipToPrevious() => _controller.previous();

  /// Mirrors the app's canonical player state into the OS media session.
  /// Called from the root Riverpod subscription, not from a second player.
  void updateFromPlayerState(
    PlayerState state,
    PlayerController controller,
  ) {
    final track = state.currentTrack;
    final isActive = track != null;
    final isPlaying = state.playbackState == contracts.PlaybackState.playing;
    final isBuffering = state.playbackState == contracts.PlaybackState.buffering ||
        state.playbackState == contracts.PlaybackState.loading ||
        state.playbackState == contracts.PlaybackState.resolving;

    if (track == null) {
      mediaItem.add(null);
      queue.add(const <audio.MediaItem>[]);
    } else {
      final currentItem = _toMediaItem(track);
      mediaItem.add(currentItem);

      final upcoming = <audio.MediaItem>[];
      for (final entry in controller.queue.upNext) {
        final info = controller.trackInfoFor(entry.trackId);
        if (info != null) upcoming.add(_toMediaItem(info));
      }
      queue.add([currentItem, ...upcoming]);
    }

    final controls = <audio.MediaControl>[
      if (isActive) audio.MediaControl.skipToPrevious,
      if (isActive)
        isPlaying || isBuffering
            ? audio.MediaControl.pause
            : audio.MediaControl.play,
      if (isActive) audio.MediaControl.skipToNext,
      if (isActive) audio.MediaControl.stop,
    ];

    playbackState.add(audio.PlaybackState(
      controls: controls,
      systemActions: const {audio.MediaAction.seek},
      androidCompactActionIndices: isActive
          ? (controls.length >= 3 ? const [0, 1, 2] : const [0])
          : const [],
      processingState: _toProcessingState(state.playbackState),
      playing: isPlaying || isBuffering,
      updatePosition: state.position,
      bufferedPosition: state.position,
      speed: 1.0,
      queueIndex: isActive ? 0 : null,
    ));
  }

  audio.MediaItem _toMediaItem(TrackInfo track) {
    final artwork = Uri.tryParse(track.artworkUrl ?? '');
    final artUri = artwork != null &&
            (artwork.scheme == 'https' || artwork.scheme == 'http')
        ? artwork
        : null;
    return audio.MediaItem(
      id: track.id,
      title: (track.title?.trim().isNotEmpty ?? false)
          ? track.title!.trim()
          : 'Unknown track',
      artist: (track.artist?.trim().isNotEmpty ?? false)
          ? track.artist!.trim()
          : 'Unknown artist',
      artUri: artUri,
      duration: track.duration > Duration.zero ? track.duration : null,
    );
  }

  audio.AudioProcessingState _toProcessingState(
    contracts.PlaybackState state,
  ) {
    switch (state) {
      case contracts.PlaybackState.idle:
        return audio.AudioProcessingState.idle;
      case contracts.PlaybackState.resolving:
      case contracts.PlaybackState.loading:
        return audio.AudioProcessingState.loading;
      case contracts.PlaybackState.buffering:
        return audio.AudioProcessingState.buffering;
      case contracts.PlaybackState.ended:
        return audio.AudioProcessingState.completed;
      case contracts.PlaybackState.failed:
        return audio.AudioProcessingState.error;
      case contracts.PlaybackState.playing:
      case contracts.PlaybackState.paused:
      case contracts.PlaybackState.seeking:
      case contracts.PlaybackState.transitioning:
      case contracts.PlaybackState.interrupted:
      case contracts.PlaybackState.offline:
        return audio.AudioProcessingState.ready;
    }
  }
}
