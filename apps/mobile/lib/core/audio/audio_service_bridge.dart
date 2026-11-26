import 'package:audio_service/audio_service.dart' as audio;
import 'package:breezze_audio_contracts/audio_contracts.dart' as contracts;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_controller.dart';
import 'background_audio.dart';

/// Native background-audio bridge over audio_service.
///
/// Lock-screen/notification media controls dispatch commands straight to
/// the global PlayerController — the controller stays the single
/// playback authority (§53.1); this handler is only the OS surface.
class AudioServiceBridge extends audio.BaseAudioHandler
    implements BackgroundAudioBridge {
  final ProviderContainer container;
  String? _lastTrackId;
  int? _lastQueueVersion;

  AudioServiceBridge(this.container);

  PlayerController get _player =>
      container.read(playerControllerProvider.notifier);

  // ---- Lock-screen commands → PlayerController ---------------------

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> seek(Duration position) => _player.seekTo(position);

  // ---- BackgroundAudioBridge (OS sync) ----------------------------

  @override
  Future<void> start() async {
    // Already initialized by the time this instance exists; nothing to do.
  }

  @override
  Future<void> update({
    required String title,
    required String artist,
    String? artworkUrl,
    required bool playing,
  }) async {
    final state = container.read(playerControllerProvider);
    final controller = _player;
    final track = state.currentTrack;
    final active = track != null;
    final buffering = state.playbackState == contracts.PlaybackState.buffering ||
        state.playbackState == contracts.PlaybackState.loading ||
        state.playbackState == contracts.PlaybackState.resolving;
    final actuallyPlaying = playing &&
        state.playbackState == contracts.PlaybackState.playing;

    final trackChanged = track?.id != _lastTrackId;
    final queueChanged = state.queueVersion != _lastQueueVersion;
    if (trackChanged) {
      _lastTrackId = track?.id;
      if (track == null) {
        mediaItem.add(null);
      } else {
        final art = Uri.tryParse(track.artworkUrl ?? '');
        mediaItem.add(audio.MediaItem(
          id: track.id,
          title: track.title?.trim().isNotEmpty == true
              ? track.title!.trim()
              : title,
          artist: track.artist?.trim().isNotEmpty == true
              ? track.artist!.trim()
              : artist,
          duration: track.duration > Duration.zero ? track.duration : null,
          artUri: art != null &&
                  (art.scheme == 'https' || art.scheme == 'http')
              ? art
              : null,
        ));
      }
    }
    if (trackChanged || queueChanged) {
      if (track == null) {
        queue.add(const <audio.MediaItem>[]);
      } else {
        final items = <audio.MediaItem>[];
        final currentArt = Uri.tryParse(track.artworkUrl ?? '');
        items.add(audio.MediaItem(
          id: track.id,
          title: track.title ?? title,
          artist: track.artist ?? artist,
          duration: track.duration > Duration.zero ? track.duration : null,
          artUri: currentArt != null &&
                  (currentArt.scheme == 'https' || currentArt.scheme == 'http')
              ? currentArt
              : null,
        ));
        for (final entry in controller.queue.upNext) {
          final info = controller.trackInfoFor(entry.trackId);
          if (info == null) continue;
          final upcomingArt = Uri.tryParse(info.artworkUrl ?? '');
          items.add(audio.MediaItem(
            id: info.id,
            title: info.title ?? 'Unknown track',
            artist: info.artist ?? 'Unknown artist',
            duration: info.duration > Duration.zero ? info.duration : null,
            artUri: upcomingArt != null &&
                    (upcomingArt.scheme == 'https' || upcomingArt.scheme == 'http')
                ? upcomingArt
                : null,
          ));
        }
        queue.add(items);
      }
      _lastQueueVersion = state.queueVersion;
    }

    audio.AudioProcessingState processingState;
    switch (state.playbackState) {
      case contracts.PlaybackState.idle:
        processingState = audio.AudioProcessingState.idle;
      case contracts.PlaybackState.resolving:
      case contracts.PlaybackState.loading:
        processingState = audio.AudioProcessingState.loading;
      case contracts.PlaybackState.buffering:
        processingState = audio.AudioProcessingState.buffering;
      case contracts.PlaybackState.ended:
        processingState = audio.AudioProcessingState.completed;
      case contracts.PlaybackState.failed:
        processingState = audio.AudioProcessingState.error;
      case contracts.PlaybackState.playing:
      case contracts.PlaybackState.paused:
      case contracts.PlaybackState.seeking:
      case contracts.PlaybackState.transitioning:
      case contracts.PlaybackState.interrupted:
      case contracts.PlaybackState.offline:
        processingState = audio.AudioProcessingState.ready;
    }

    final controls = <audio.MediaControl>[
      if (active) audio.MediaControl.skipToPrevious,
      if (active)
        actuallyPlaying || buffering
            ? audio.MediaControl.pause
            : audio.MediaControl.play,
      if (active) audio.MediaControl.skipToNext,
      if (active) audio.MediaControl.stop,
    ];
    playbackState.add(audio.PlaybackState(
      controls: controls,
      systemActions: const {audio.MediaAction.seek},
      androidCompactActionIndices:
          active ? const [0, 1, 2] : const <int>[],
      processingState: processingState,
      playing: actuallyPlaying || buffering,
      updatePosition: state.position,
      bufferedPosition: state.position,
      speed: 1.0,
      queueIndex: active ? 0 : null,
    ));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _lastTrackId = null;
    _lastQueueVersion = null;
    mediaItem.add(null);
    queue.add(const <audio.MediaItem>[]);
    await super.stop();
  }
}

/// Platform eligibility is separately testable without native OS plugins.
///
/// Browser playback follows the web engine's browser/visibility policy.
/// Linux needs a desktop D-Bus/MPRIS session; Windows needs SMTC; macOS
/// uses the audio_service native plugin. Initialization may still fail and
/// must not prevent the listener from using the application.
bool supportsBreezzeSystemMediaSession(TargetPlatform platform, {
  bool isWeb = false,
}) {
  if (isWeb) return false;
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
}

/// Starts ONE audio_service handler as the OS projection of PlayerController.
///
/// Mac/Windows/Linux support is a capability attempt, not a claim of
/// certified media-key or OS notification behavior. Failure to establish a
/// native OS media session must not create a second controller or stop local
/// audio playback.
Future<BackgroundAudioBridge> startBackgroundAudio(
    ProviderContainer container) async {
  if (!supportsBreezzeSystemMediaSession(
    defaultTargetPlatform,
    isWeb: kIsWeb,
  )) {
    return NoopBackgroundBridge();
  }

  try {
    return await audio.AudioService.init<AudioServiceBridge>(
      builder: () => AudioServiceBridge(container),
      config: const audio.AudioServiceConfig(
        androidNotificationChannelId: 'com.breezze.audio',
        androidNotificationChannelName: 'Breezze playback',
        androidNotificationChannelDescription:
            'Playback controls for Breezze',
        androidNotificationIcon: 'drawable/ic_breezze_notification',
        androidStopForegroundOnPause: false,
      ),
    );
  } catch (error) {
    // A minimal Linux distro may lack a user D-Bus session; a Windows
    // runner may not expose SMTC. Neither failure should crash the app.
    // Do not claim an OS bridge is active in this fallback.
    return NoopBackgroundBridge();
  }
}
