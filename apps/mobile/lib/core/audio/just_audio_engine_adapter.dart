import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// Native audio engine — implements the Breezze engine contract over
/// just_audio, which wraps ExoPlayer (Android) and AVFoundation (iOS).
class JustAudioEngineAdapter implements AudioEngineAdapter {
  // The Breezze controller owns interruption decisions. just_audio's
  // automatic interruption handler can auto-resume after calls, contrary
  // to our privacy-conscious "resume only on user request" policy.
  // Its native audio-session activation remains enabled: it requests OS
  // focus only when playback actually starts.
  final ja.AudioPlayer _player = ja.AudioPlayer(handleInterruptions: false);
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  late final StreamSubscription<ja.PlaybackEvent> _errorSubscription;
  late final StreamSubscription<ja.PlayerState> _stateSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  bool _disposed = false;
  late final Future<void> _sessionReady;

  JustAudioEngineAdapter() {
    _errorSubscription = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed) _states.add(PlaybackState.failed);
      },
    );
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (_disposed) return;
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
    // Awaited before resolving the first playable source, so the session
    // category and event subscriptions cannot race with initial playback.
    _sessionReady = _configureAudioSession();
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
      // Native audio plugins can be unavailable on headless test runners.
      // A bounded fallback avoids blocking the first song indefinitely;
      // just_audio retains its own OS focus activation at play().
      final session = await AudioSession.instance
          .timeout(const Duration(seconds: 5));
      if (_disposed) return;
      await session.configure(const AudioSessionConfiguration.music())
          .timeout(const Duration(seconds: 5));
      if (_disposed) return;
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (_disposed) return;
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
        if (_disposed) return;
        // Headphones/Bluetooth route removed: pause to avoid speaker leakage.
        unawaited(_player.pause().catchError((_) {}));
      });
    } catch (_) {
      // Audio session integration is best-effort; core playback remains usable.
    }
  }

  @override
  Future<void> prepare(PlayableSource source) async {
    await _sessionReady;
    if (_disposed) throw StateError('Breezze audio engine is disposed');
    if (source.isLocal && !kIsWeb && !source.streamUrl.startsWith('content://')) {
      await _player.setFilePath(source.streamUrl);
    } else {
      await _player.setUrl(source.streamUrl);
    }
  }

  @override
  Future<void> play() async {
    await _sessionReady;
    if (_disposed) throw StateError('Breezze audio engine is disposed');
    // just_audio.play() returns a Future that completes on TRACK END/PAUSE,
    // NOT when playback starts. Awaiting it here deadlocks the caller's
    // playTrack() command for the full song and breaks native acceptance.
    // Start the native player once; follow state/error events separately.
    // Playback completion belongs to the engineStateStream, not this command.
    unawaited(_player.play().catchError((Object error, StackTrace trace) {
      if (!_disposed && !_states.isClosed) {
        _states.add(PlaybackState.failed);
      }
    }));
  }

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
    if (_disposed) return;
    _disposed = true;
    // An in-flight session setup must not install listeners after disposal.
    await _sessionReady;
    await _errorSubscription.cancel();
    await _stateSubscription.cancel();
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    await _states.close();
    await _player.dispose();
  }
}
