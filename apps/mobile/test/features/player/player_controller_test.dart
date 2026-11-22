import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:breezze/features/player/player_controller.dart';
import 'package:breezze/features/player/playback_session_client.dart';
import 'package:breezze/features/player/playback_heartbeat_store.dart';
import 'package:breezze/core/auth/auth_session.dart';

void main() {
  test('metadata-only provider tracks never enter the native resolver', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
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
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
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
    await player.seekTo(const Duration(seconds: 42));
    expect(player.state.position, const Duration(seconds: 42));

    await player.pause();
    expect(player.state.playbackState, PlaybackState.paused);
    await player.seekTo(const Duration(seconds: 55));
    expect(player.state.position, const Duration(seconds: 55));

    await player.resume();
    expect(resolver.calls, 2);
    expect(engine.prepareCount, 2);
    expect(engine.lastSeekPosition, const Duration(seconds: 55));
    expect(player.state.position, const Duration(seconds: 55));
    expect(player.state.playbackState, PlaybackState.playing);
  });
  test('server session follows pause, resume, track switch and stop', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'bz:audius:session-one',
          streamUrl: 'https://media.example/one.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'session-one',
        ),
        PlayableSource(
          trackId: 'bz:audius:session-two',
          streamUrl: 'https://media.example/two.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'session-two',
        ),
      ];
    final client = _FakePlaybackSessionClient();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackSessionClientProvider.overrideWithValue(client),
      authSessionProvider.overrideWith(_SignedInAuthController.new),
      playbackHeartbeatStoreProvider.overrideWithValue(_MemoryHeartbeatStore()),
      playbackHeartbeatIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const first = TrackInfo(id: 'bz:audius:session-one', title: 'One');
    const second = TrackInfo(id: 'bz:audius:session-two', title: 'Two');

    await player.playTrack(trackId: first.id, queue: const [first]);
    await player.pause();
    expect(client.paused, ['session-one']);
    await player.resume();
    expect(client.resumed, ['session-one']);

    await player.playTrack(trackId: second.id, queue: const [second]);
    expect(client.stopped, ['session-one']);
    await player.stop();
    expect(client.stopped, ['session-one', 'session-two']);
  });

  test('heartbeat retries reuse the same event ID and sequence until acknowledged', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'bz:audius:heartbeat',
          streamUrl: 'https://media.example/heartbeat.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'heartbeat-session',
        ),
      ];
    final client = _FakePlaybackSessionClient()..failFirstHeartbeat = true;
    final store = _MemoryHeartbeatStore();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackSessionClientProvider.overrideWithValue(client),
      authSessionProvider.overrideWith(_SignedInAuthController.new),
      playbackHeartbeatStoreProvider.overrideWithValue(store),
      playbackHeartbeatIntervalProvider.overrideWithValue(const Duration(milliseconds: 5)),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const track = TrackInfo(id: 'bz:audius:heartbeat', title: 'Heartbeat');
    await player.playTrack(trackId: track.id, queue: const [track]);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await player.pause();

    expect(client.heartbeatCalls.length, greaterThanOrEqualTo(2));
    expect(client.heartbeatCalls[0]['eventId'], client.heartbeatCalls[1]['eventId']);
    expect(client.heartbeatCalls[0]['sequence'], client.heartbeatCalls[1]['sequence']);
    final checkpoint = await store.read('listener-1', 'heartbeat-session');
    expect(checkpoint, isNotNull);
    expect(checkpoint!.sequence, greaterThan(1));
    expect(checkpoint.pendingEventId, isNull);
    await player.stop();
  });


  test('pending heartbeat survives a new player and is replayed for its owner', () async {
    final store = _MemoryHeartbeatStore();
    await store.write(const PlaybackHeartbeatCheckpoint(
      ownerId: 'listener-1',
      sessionId: 'previous-session',
      sequence: 7,
      pendingEventId: 'stable-event-id',
    ));
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'bz:audius:recovery',
          streamUrl: 'https://media.example/recovery.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'new-session',
        ),
      ];
    final client = _FakePlaybackSessionClient();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackSessionClientProvider.overrideWithValue(client),
      authSessionProvider.overrideWith(_SignedInAuthController.new),
      playbackHeartbeatStoreProvider.overrideWithValue(store),
      playbackHeartbeatIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    await player.playTrack(
      trackId: 'bz:audius:recovery',
      queue: const [TrackInfo(id: 'bz:audius:recovery', title: 'Recovery')],
    );

    expect(client.heartbeatCalls, [
      {
        'sessionId': 'previous-session',
        'eventId': 'stable-event-id',
        'sequence': 7,
      },
    ]);
    expect(await store.read('listener-1', 'previous-session'), isNull);
    await player.stop();
  });

  test('failed native play closes the authorized server session', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'bz:audius:play-failure',
          streamUrl: 'https://media.example/failure.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'play-failure-session',
        ),
      ];
    final client = _FakePlaybackSessionClient();
    final engine = _FakeAudioEngine()..failPlay = true;
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackSessionClientProvider.overrideWithValue(client),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const track = TrackInfo(id: 'bz:audius:play-failure', title: 'Failure');
    await player.playTrack(trackId: track.id, queue: const [track]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(player.state.playbackState, PlaybackState.failed);
    expect(client.stopped, ['play-failure-session']);
  });

  test('OS audio interruption pauses and requires an explicit resume', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const track = TrackInfo(
      id: 'bz:audius:interrupt-test',
      title: 'Interruption test',
      artist: 'Example Artist',
    );
    await player.playTrack(trackId: track.id, queue: const [track]);
    expect(player.state.playbackState, PlaybackState.playing);

    engine.emit(PlaybackState.interrupted);
    await Future<void>.delayed(Duration.zero);
    expect(player.state.playbackState, PlaybackState.interrupted);

    engine.emit(PlaybackState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(player.state.playbackState, PlaybackState.paused);

    await player.resume();
    expect(player.state.playbackState, PlaybackState.playing);
  });

  test('completed track advances the single global queue exactly once', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const first = TrackInfo(
      id: 'bz:audius:queue-first',
      title: 'First track',
      artist: 'Example Artist',
    );
    const second = TrackInfo(
      id: 'bz:audius:queue-second',
      title: 'Second track',
      artist: 'Example Artist',
    );

    await player.playTrack(
      trackId: first.id,
      queue: const [first, second],
      startIndex: 0,
    );
    expect(player.state.currentTrack?.id, first.id);
    expect(resolver.calls, 1);

    engine.emit(PlaybackState.ended);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(player.state.currentTrack?.id, second.id);
    expect(resolver.calls, 2);

    // Duplicate completion notifications for the same item must not skip
    // another queue entry or trigger a second resolver request.
    engine.emit(PlaybackState.ended);
    await Future<void>.delayed(Duration.zero);
    expect(player.state.currentTrack?.id, second.id);
    expect(resolver.calls, 2);
  });

}

class _FakePlaybackSessionClient implements PlaybackSessionClient {
  final List<String> paused = [];
  final List<String> resumed = [];
  final List<String> stopped = [];
  final List<Map<String, Object>> heartbeatCalls = [];
  bool failFirstHeartbeat = false;

  @override
  Future<Map<String, dynamic>> heartbeat({
    required String sessionId,
    required String eventId,
    required int sequence,
  }) async {
    heartbeatCalls.add({
      'sessionId': sessionId,
      'eventId': eventId,
      'sequence': sequence,
    });
    if (failFirstHeartbeat && heartbeatCalls.length == 1) {
      throw StateError('temporary network failure');
    }
    return {'accepted': true};
  }

  @override
  Future<void> pause(String sessionId) async { paused.add(sessionId); }

  @override
  Future<void> resume(String sessionId) async { resumed.add(sessionId); }

  @override
  Future<void> stop(String sessionId) async { stopped.add(sessionId); }
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
    return sources[index.clamp(0, sources.length - 1).toInt()];
  }
}

class _FakeAudioEngine implements AudioEngineAdapter {
  final _positions = StreamController<Duration>.broadcast();
  final _states = StreamController<PlaybackState>.broadcast();
  int prepareCount = 0;
  Duration? lastSeekPosition;
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

  bool failPlay = false;

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('native play failed');
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
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

  void emit(PlaybackState state) => _states.add(state);

  Future<void> dispose() async {
    await _positions.close();
    await _states.close();
  }
}


class _SignedInAuthController extends AuthSessionController {
  @override
  AuthState build() => const AuthSignedIn(
        userId: 'listener-1',
        email: 'listener@example.test',
      );
}

class _MemoryHeartbeatStore implements PlaybackHeartbeatStore {
  final Map<String, PlaybackHeartbeatCheckpoint> _items = {};

  String _key(String ownerId, String sessionId) => '$ownerId::$sessionId';

  @override
  Future<PlaybackHeartbeatCheckpoint?> read(
    String ownerId,
    String sessionId,
  ) async => _items[_key(ownerId, sessionId)];

  @override
  Future<List<PlaybackHeartbeatCheckpoint>> pendingForOwner(
    String ownerId,
  ) async =>
      _items.values
          .where((item) =>
              item.ownerId == ownerId && item.pendingEventId != null)
          .toList(growable: false);

  @override
  Future<void> write(PlaybackHeartbeatCheckpoint checkpoint) async {
    _items[_key(checkpoint.ownerId, checkpoint.sessionId)] = checkpoint;
  }

  @override
  Future<void> clear(String ownerId, String sessionId) async {
    _items.remove(_key(ownerId, sessionId));
  }
}
