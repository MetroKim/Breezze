import 'dart:async';

import 'package:breezze/core/audio/audio_service_bridge.dart';
import 'package:breezze/core/audio/playback_queue_store.dart';
import 'package:breezze/features/player/player_controller.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

class _NativeQaResolver implements PlaybackResolver {
  int grants = 0;

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    grants++;
    return PlayableSource(
      trackId: track.id,
      streamUrl: 'https://breezze.example.test/audio/grant-${grants}',
      expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 2)),
    );
  }
}

class _NativeQaEngine implements AudioEngineAdapter {
  final events = StreamController<PlaybackState>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  int prepares = 0;
  int starts = 0;
  Duration? lastSeek;

  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Duration get position => lastSeek ?? Duration.zero;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<PlaybackState> get engineStateStream => events.stream;

  @override
  Future<void> prepare(PlayableSource source) async { prepares++; }
  @override
  Future<void> play() async { starts++; }
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    positions.add(position);
  }
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double rate) async {}

  Future<void> close() async {
    await events.close();
    await positions.close();
  }
}

const _one = TrackInfo(
  id: 'bz:jamendo:native-qa-one',
  title: 'Native QA One',
  artist: 'Breezze QA',
);
const _two = TrackInfo(
  id: 'bz:jamendo:native-qa-two',
  title: 'Native QA Two',
  artist: 'Breezze QA',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native media bridge controls the one global playback authority',
      (tester) async {
    final engine = _NativeQaEngine();
    final resolver = _NativeQaResolver();
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(resolver),
    ]);
    addTearDown(() async {
      container.dispose();
      await engine.close();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('Breezze native media acceptance')),
    ));

    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    final bridge = AudioServiceBridge(container);
    await player.playTrack(trackId: _one.id, queue: const [_one, _two]);
    await bridge.update(title: 'Native QA One', artist: 'Breezze QA', playing: true);
    expect(bridge.mediaItem.value?.id, _one.id);
    expect(bridge.queue.value.length, 2);
    expect(player.state.playbackState, PlaybackState.playing);

    await bridge.pause();
    expect(player.state.playbackState, PlaybackState.paused);
    await bridge.seek(const Duration(seconds: 37));
    expect(player.state.position, const Duration(seconds: 37));
    await bridge.play();
    expect(player.state.playbackState, PlaybackState.playing);

    // A phone call/audio-focus interruption must not silently auto-resume.
    engine.events.add(PlaybackState.interrupted);
    await tester.pump();
    expect(player.state.playbackState, PlaybackState.interrupted);
    engine.events.add(PlaybackState.paused);
    await tester.pump();
    expect(player.state.playbackState, PlaybackState.paused);
    await bridge.play();
    expect(player.state.playbackState, PlaybackState.playing);

    await bridge.skipToNext();
    expect(player.state.currentTrack?.id, _two.id);
    await bridge.skipToPrevious();
    expect(player.state.currentTrack?.id, _one.id);

    await bridge.stop();
    expect(player.state.playbackState, PlaybackState.idle);
    expect(bridge.queue.value, isEmpty);
  });

  testWidgets('native encrypted queue survives restart without stale media grant',
      (tester) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final ownerA = 'native-queue-a-$id';
    final ownerB = 'native-queue-b-$id';
    final store = PlaybackQueueStore();
    final originalEngine = _NativeQaEngine();
    final original = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWithValue(_NativeQaResolver()),
    ]);
    addTearDown(() async {
      original.dispose();
      await originalEngine.close();
    });
    final originalPlayer = original.read(playerControllerProvider.notifier);
    originalPlayer.attachEngine(originalEngine);
    await originalPlayer.playTrack(trackId: _one.id, queue: const [_one, _two]);
    await originalPlayer.seekTo(const Duration(seconds: 20));
    final snapshot = originalPlayer.exportQueueSnapshot()!;
    try {
      await store.save(ownerA, snapshot);
      expect(await store.load(ownerB), isNull);
      final recovered = await store.load(ownerA);
      expect(recovered, isNotNull);
      expect(recovered.toString(), isNot(contains('/audio/grant-')));

      final newEngine = _NativeQaEngine();
      final newResolver = _NativeQaResolver();
      final restarted = ProviderContainer(overrides: [
        playbackResolverProvider.overrideWithValue(newResolver),
      ]);
      addTearDown(() async {
        restarted.dispose();
        await newEngine.close();
      });
      final player = restarted.read(playerControllerProvider.notifier);
      player.attachEngine(newEngine);
      expect(player.restoreQueueSnapshot(recovered!), isTrue);
      expect(player.state.playbackState, PlaybackState.paused);
      expect(newEngine.prepares, 0);
      expect(newResolver.grants, 0);

      await player.resume();
      expect(newResolver.grants, 1);
      expect(newEngine.prepares, 1);
      expect(newEngine.lastSeek, const Duration(seconds: 20));
    } finally {
      await store.clear(ownerA);
      await store.clear(ownerB);
    }
  });
}
