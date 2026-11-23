import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// Native audio engine — implements the Breezze engine contract over
/// just_audio, which wraps ExoPlayer (Android) and AVFoundation (iOS).
class JustAudioEngineAdapter implements AudioEngineAdapter {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  late final StreamSubscription<ja.PlaybackEvent> _errorSubscription;
  late final StreamSubscription<ja.PlayerState> _stateSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  bool _disposed = false;

  JustAudioEngineAdapter() {
    _errorSubscription = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _states.add(PlaybackState.failed);
      },
    );
    _stateSubscription = _player.playerStateStream.listen((state) {
      PlaybackState mapped;
      final processing = state.processingState;

      if (processing == ja.ProcessingState.loading ||
          processing == ja.ProcessingState.buffering) {
        mapped = PlaybackState.buffering;
      } else if (processing == ja.ProcessingState.completed) {
        mapped = PlaybackState.ended;
      } else if (processing == ja.ProcessingState.idle) {
        mapped = PlaybackState.idle;
      } else if (state.playing && processing == ja.ProcessingState.ready) {
        mapped = PlaybackState.playing;
      } else {
        mapped = PlaybackState.paused;
      }
      _states.add(mapped);
    });
    unawaited(_configureAudioSession());
  }

  Future<void> _configureAudioSession() async {
    // Audio focus and headphone events are mobile OS concerns. Desktop and
    // web use their own platform audio policies and must not require this plugin.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      if (_disposed) return;
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Pause rather than duck for calls, navigation prompts and other
          // exclusive audio interruptions. Never auto-resume after a call.
          unawaited(_player.pause().catchError((_) {}));
          _states.add(PlaybackState.interrupted);
        } else {
          _states.add(PlaybackState.paused);
        }
      });
      _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
        // Headphones/Bluetooth route removed: pause to avoid speaker leakage.
        unawaited(_player.pause().catchError((_) {}));
      });
    } catch (_) {
      // Audio session integration is best-effort; core playback remains usable.
    }
  }

  @override
  Future<void> prepare(PlayableSource source) async {
    if (source.isLocal && !kIsWeb && !source.streamUrl.startsWith('content://')) {
      await _player.setFilePath(source.streamUrl);
    } else {
      await _player.setUrl(source.streamUrl);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Duration get position => _player.position;

  @override
  Duration get duration => _player.duration ?? Duration.zero;

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSpeed(double rate) => _player.setSpeed(rate);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<PlaybackState> get engineStateStream => _states.stream;

  Future<void> dispose() async {
    _disposed = true;
    await _errorSubscription.cancel();
    await _stateSubscription.cancel();
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    await _states.close();
    await _player.dispose();
  }
}
