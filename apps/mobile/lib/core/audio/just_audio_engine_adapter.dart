import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:just_audio/just_audio.dart';

/// Native audio engine — implements the Breezze engine contract over
/// just_audio, which wraps ExoPlayer (Android) and AVFoundation (iOS).
class JustAudioEngineAdapter implements AudioEngineAdapter {
  final AudioPlayer _player = AudioPlayer();
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  late final StreamSubscription<PlayerException> _errorSubscription;

  JustAudioEngineAdapter() {
    _errorSubscription = _player.errorStream.listen((_) {
      _states.add(PlaybackState.failed);
    });
    _player.playerStateStream.listen((state) {
      PlaybackState mapped;
      final processing = state.processingState;

      if (processing == ProcessingState.loading ||
          processing == ProcessingState.buffering) {
        mapped = PlaybackState.buffering;
      } else if (processing == ProcessingState.completed) {
        mapped = PlaybackState.ended;
      } else if (state.playing) {
        mapped = PlaybackState.playing;
      } else {
        mapped = PlaybackState.paused;
      }
      _states.add(mapped);
    });
  }

  @override
  Future<void> prepare(PlayableSource source) async {
    if (source.isLocal) {
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
    await _errorSubscription.cancel();
    await _states.close();
    await _player.dispose();
  }
}
