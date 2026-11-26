import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:breezze/features/player/player_controller.dart';
import 'package:breezze/core/audio/playback_recovery_policy.dart';
import 'package:breezze/features/player/playback_session_client.dart';

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

  test('paused playback refreshes an expired authorized grant before resume', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'catalog-qa:expired-grant',
          streamUrl: 'https://cdn.example.com/audio.m4a',
          expiresAtUtc: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        ),
        PlayableSource(
          trackId: 'catalog-qa:expired-grant',
          streamUrl: 'https://cdn.example.com/audio.m4a',
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
      id: 'catalog-qa:expired-grant',
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
          trackId: 'catalog-qa:session-one',
          streamUrl: 'https://media.example/one.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'session-one',
        ),
        PlayableSource(
          trackId: 'catalog-qa:session-two',
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
      playbackHeartbeatIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const first = TrackInfo(id: 'catalog-qa:session-one', title: 'One');
    const second = TrackInfo(id: 'catalog-qa:session-two', title: 'Two');

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
          trackId: 'catalog-qa:heartbeat',
          streamUrl: 'https://media.example/heartbeat.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sessionId: 'heartbeat-session',
        ),
      ];
    final client = _FakePlaybackSessionClient()..failFirstHeartbeat = true;
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackSessionClientProvider.overrideWithValue(client),
      playbackHeartbeatIntervalProvider.overrideWithValue(const Duration(milliseconds: 5)),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const track = TrackInfo(id: 'catalog-qa:heartbeat', title: 'Heartbeat');
    await player.playTrack(trackId: track.id, queue: const [track]);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await player.pause();

    expect(client.heartbeatCalls.length, greaterThanOrEqualTo(2));
    expect(client.heartbeatCalls[0]['eventId'], client.heartbeatCalls[1]['eventId']);
    expect(client.heartbeatCalls[0]['sequence'], client.heartbeatCalls[1]['sequence']);
    await player.stop();
  });

  test('failed native play closes the authorized server session', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'catalog-qa:play-failure',
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
    const track = TrackInfo(id: 'catalog-qa:play-failure', title: 'Failure');
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
      id: 'catalog-qa:interrupt-test',
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
      id: 'catalog-qa:queue-first',
      title: 'First track',
      artist: 'Example Artist',
    );
    const second = TrackInfo(
      id: 'catalog-qa:queue-second',
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



  test('licensed full-song source preserves next-track queue order', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() async { container.dispose(); await engine.dispose(); });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const queue = [
      TrackInfo(id: 'catalog-qa:queue-first', title: 'First'),
      TrackInfo(id: 'catalog-qa:queue-second', title: 'Second'),
    ];

    await player.playTrack(trackId: queue.first.id, queue: queue, startIndex: 0);
    expect(player.state.currentTrack?.id, queue.first.id);
    expect(player.state.playbackState, PlaybackState.playing);

    engine.emit(PlaybackState.ended);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(player.state.currentTrack?.id, queue.last.id);
    expect(player.state.playbackState, PlaybackState.playing);
    expect(resolver.calls, 2);
    expect(engine.prepareCount, 2);
  });

  test('restored queue is paused and must resolve a new authorized URL', () async {
    final originalResolver = _FakeResolver();
    final originalEngine = _FakeAudioEngine();
    final original = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(originalResolver),
    ]);
    addTearDown(() async {
      original.dispose();
      await originalEngine.dispose();
    });
    final player = original.read(playerControllerProvider.notifier);
    player.attachEngine(originalEngine);
    const first = TrackInfo(id: 'catalog-qa:restore-1',
        title: 'Resume this track', artist: 'Breezze QA');
    const second = TrackInfo(id: 'catalog-qa:restore-2',
        title: 'Upcoming', artist: 'Breezze QA');
    await player.playTrack(trackId: first.id, queue: const [first, second]);
    await player.seekTo(const Duration(seconds: 36));
    player.toggleShuffle();
    final serialized = player.exportQueueSnapshot()!;
    expect(serialized.toString(), isNot(contains('https://media.example')));
    expect(serialized.toString(), isNot(contains('sessionId')));
    expect(serialized['positionMs'], 36000);

    final newResolver = _FakeResolver();
    final newEngine = _FakeAudioEngine();
    final fresh = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(newResolver),
    ]);
    addTearDown(() async {
      fresh.dispose();
      await newEngine.dispose();
    });
    final restored = fresh.read(playerControllerProvider.notifier);
    restored.attachEngine(newEngine);
    expect(restored.restoreQueueSnapshot(serialized), isTrue);
    expect(restored.state.currentTrack?.title, first.title);
    expect(restored.state.playbackState, PlaybackState.paused);
    expect(restored.state.position, const Duration(seconds: 36));
    expect(restored.queue.shuffle, isTrue);
    expect(newEngine.prepareCount, 0);
    expect(newResolver.calls, 0);

    newEngine.emit(PlaybackState.idle);
    await Future<void>.delayed(Duration.zero);
    expect(restored.state.playbackState, PlaybackState.paused);

    await restored.resume();
    expect(newResolver.calls, 1);
    expect(newEngine.prepareCount, 1);
    expect(newEngine.lastSeekPosition, const Duration(seconds: 36));
    expect(restored.state.playbackState, PlaybackState.playing);
  });

  test('queue restoration rejects metadata-only and corrupt snapshots', () {
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(_FakeResolver()),
    ]);
    addTearDown(container.dispose);
    final player = container.read(playerControllerProvider.notifier);
    final snapshot = <String, dynamic>{
      'v': 1,
      'selected': 'one',
      'entries': [
        {'id': 'one', 'track': 'bz:apple_catalog:123', 'origin': 'fake'}
      ],
      'tracks': [
        {'id': 'bz:apple_catalog:123', 'title': 'Unlicensed'}
      ],
    };
    expect(player.restoreQueueSnapshot(snapshot), isFalse);
    expect(player.state.playbackState, PlaybackState.idle);
  });


  test('expired backend session re-resolves on resume instead of reusing old media', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'catalog-qa:session-expiry',
          streamUrl: 'https://media.example/old.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 6)),
          sessionId: 'expired-server-session',
        ),
        PlayableSource(
          trackId: 'catalog-qa:session-expiry',
          streamUrl: 'https://media.example/new.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          sessionId: 'fresh-server-session',
        ),
      ];
    final client = _FakePlaybackSessionClient()..rejectNextResume = true;
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackSessionClientProvider.overrideWithValue(client),
      playbackHeartbeatIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
    });
    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    const track = TrackInfo(id: 'catalog-qa:session-expiry', title: 'Session renewal QA');
    await player.playTrack(trackId: track.id, queue: const [track]);
    await player.seekTo(const Duration(seconds: 33));
    await player.pause();
    expect(player.state.playbackState, PlaybackState.paused);

    await player.resume();

    expect(resolver.calls, 2);
    expect(engine.prepareCount, 2);
    expect(engine.lastSeekPosition, const Duration(seconds: 33));
    expect(player.state.playbackState, PlaybackState.playing);
    expect(player.state.currentTrack?.id, track.id);
    expect(client.stopped, contains('expired-server-session'));
    await player.stop();
    expect(client.stopped, contains('fresh-server-session'));
  });

  test('stream failure refreshes the authorized URL and preserves seek position', () async {
    final resolver = _FakeResolver()
      ..sources = [
        PlayableSource(
          trackId: 'licensed-reconnect',
          streamUrl: 'https://cdn.example/old.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        ),
        PlayableSource(
          trackId: 'licensed-reconnect',
          streamUrl: 'https://cdn.example/fresh.mp3',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        ),
      ];
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackRecoveryDelaysProvider.overrideWithValue([
        const Duration(milliseconds: 1),
      ]),
    ]);
    addTearDown(() async { container.dispose(); await engine.dispose(); });

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    await player.playTrack(trackId: 'licensed-reconnect',
        title: 'Full song');
    await player.seekTo(const Duration(seconds: 47));
    engine.emit(PlaybackState.failed);
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(resolver.calls, 2);
    expect(engine.prepareCount, 2);
    expect(engine.lastSeekPosition, const Duration(seconds: 47));
    expect(player.state.currentTrack?.id, 'licensed-reconnect');
    expect(player.state.playbackState, PlaybackState.playing);
  });

  test('stream recovery stops after the bounded retry budget', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackRecoveryDelaysProvider.overrideWithValue([
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 1),
      ]),
    ]);
    addTearDown(() async { container.dispose(); await engine.dispose(); });
    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    await player.playTrack(trackId: 'licensed-retry-limit');

    for (var i = 0; i < 3; i++) {
      engine.emit(PlaybackState.failed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(resolver.calls, 3);
    expect(player.state.playbackState, PlaybackState.failed);
  });

  test('explicit stop cancels a pending live stream recovery', () async {
    final resolver = _FakeResolver();
    final engine = _FakeAudioEngine();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
      playbackRecoveryDelaysProvider.overrideWithValue([
        const Duration(milliseconds: 50),
      ]),
    ]);
    addTearDown(() async { container.dispose(); await engine.dispose(); });
    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    await player.playTrack(trackId: 'licensed-stop');
    engine.emit(PlaybackState.failed);
    await Future<void>.delayed(Duration.zero);
    await player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 65));

    expect(resolver.calls, 1);
    expect(player.state.playbackState, PlaybackState.idle);
  });


}

class _FakePlaybackSessionClient implements PlaybackSessionClient {
  final List<String> paused = [];
  final List<String> resumed = [];
  final List<String> stopped = [];
  final List<Map<String, Object>> heartbeatCalls = [];
  bool failFirstHeartbeat = false;
  bool rejectNextResume = false;

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
  Future<void> resume(String sessionId) async {
    if (rejectNextResume) {
      rejectNextResume = false;
      throw StateError('SERVER_SESSION_EXPIRED');
    }
    resumed.add(sessionId);
  }

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
