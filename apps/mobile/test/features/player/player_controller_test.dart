import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:breezze/features/player/player_controller.dart';

void main() {
  test('metadata-only provider tracks never enter the native resolver', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() {
      container.dispose();
      engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    await player.playTrack(
      trackId: 'bz:youtube_music:video123',
      title: 'Metadata only',
      artist: 'Example Artist',
      queue: const [
        TrackInfo(
          id: 'bz:youtube_music:video123',
          title: 'Metadata only',
          artist: 'Example Artist',
        ),
      ],
    );

    expect(resolver.calls, 0);
    expect(player.state.playbackState, PlaybackState.idle);
  });

  test('paused playback refreshes an expired provider grant before resume', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'bz:audius:track123',
          streamUrl: 'https://api.audius.co/v1/tracks/track123/stream',
          expiresAtUtc: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        ),
        PlayableSource(
          trackId: 'bz:audius:track123',
          streamUrl: 'https://api.audius.co/v1/tracks/track123/stream',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        ),
      ];
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() {
      container.dispose();
      engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const track = TrackInfo(
      id: 'bz:audius:track123',
      title: 'Playable track',
      artist: 'Example Artist',
    );

    await player.playTrack(
      trackId: track.id,
      queue: const [track],
    );
    expect(player.state.playbackState, PlaybackState.playing);
    expect(resolver.calls, 1);
    expect(engine.prepareCount, 1);

    await player.pause();
    expect(player.state.playbackState, PlaybackState.paused);

    await player.resume();
    expect(resolver.calls, 2);
    expect(engine.prepareCount, 2);
    expect(player.state.playbackState, PlaybackState.playing);
  });
}

class _FakeResolver implements PlaybackResolver {
  int calls = 0;
  List<PlayableSource> sources = [];

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    final index = calls++;
    if (sources.isEmpty) {
      return PlayableSource(
        trackId: track.id,
        streamUrl: 'https://media.example/track.mp3',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
    }
    return sources[index.clamp(0, sources.length - 1)];
  }
}

class _FakeAudioEngine implements AudioEngineAdapter {
  final _positions = StreamController<Duration>.broadcast();
  final _states = StreamController<PlaybackState>.broadcast();
  int prepareCount = 0;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 3);

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<PlaybackState> get engineStateStream => _states.stream;

  @override
  Future<void> prepare(PlayableSource source) async {
    prepareCount++;
    _position = Duration.zero;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positions.add(position);
  }

  @override
  Future<void> stop() async {
    _position = Duration.zero;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double rate) async {}

  Future<void> dispose() async {
    await _positions.close();
    await _states.close();
  }
}
