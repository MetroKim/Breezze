import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:breezze/core/audio/audio_service_bridge.dart';
import 'package:breezze/core/audio/just_audio_engine_adapter.dart';
import 'package:breezze/core/audio/playback_queue_store.dart';
import 'package:breezze/features/player/player_controller.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

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
  id: 'catalog-qa:native-qa-one',
  title: 'Native QA One',
  artist: 'Breezze QA',
);
const _two = TrackInfo(
  id: 'catalog-qa:native-qa-two',
  title: 'Native QA Two',
  artist: 'Breezze QA',
);


Uint8List _testStereoWav({int sampleRate = 44100, int seconds = 3}) {
  const channels = 2;
  const bytesPerSample = 2;
  const header = 44;
  final dataSize = sampleRate * seconds * channels * bytesPerSample;
  final data = ByteData(header + dataSize);
  void tag(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }
  tag(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  for (var frame = 0; frame < sampleRate * seconds; frame++) {
    final sample = (math.sin(frame * 2 * math.pi * 440 / sampleRate) * 7000).round();
    data.setInt16(header + frame * 4, sample, Endian.little);
    data.setInt16(header + frame * 4 + 2, sample, Endian.little);
  }
  return data.buffer.asUint8List();
}


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

  testWidgets('real native engine decodes an official Deezer preview over HTTPS',
      (tester) async {
    // Verify the actual supported preview path, not metadata-only "playback".
    // Deezer provides a limited preview; no full song, bypass, cookie, media
    // extraction or offline copy is needed for this test.
    final payload = await tester.runAsync(() async {
      final response = await http.get(
        Uri.https('api.deezer.com', '/track/3135553'),
      ).timeout(const Duration(seconds: 12));
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
    expect(payload, isNotNull);
    expect(payload!['id'], 3135553);
    final preview = Uri.tryParse(payload['preview'] as String? ?? '');
    expect(preview, isNotNull);
    expect(preview!.scheme, 'https');
    expect(preview.host.endsWith('.dzcdn.net'), isTrue,
        reason: 'Deezer preview must remain on the official provider CDN');

    final engine = JustAudioEngineAdapter();
    try {
      await tester.runAsync(() async {
        await engine.prepare(PlayableSource(
          trackId: 'bz:deezer_preview:3135553',
          streamUrl: preview.toString(),
          expiresAtUtc: DateTime.now().toUtc()
              .add(const Duration(minutes: 1)),
        )).timeout(const Duration(seconds: 25));
      });
      expect(engine.duration, greaterThan(const Duration(seconds: 5)),
          reason: 'Native decoder must parse real streamed MP3 duration');
      unawaited(engine.play());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await engine.pause();
        await engine.seek(const Duration(seconds: 3));
      });
      expect(engine.position.inSeconds, greaterThanOrEqualTo(3));
      await engine.stop();
    } finally {
      await engine.dispose();
    }
  });

  testWidgets('native decoder handles full-length app-owned audio and far seek',
      (tester) async {
    // A real 125-second recording, intentionally not a preview or a
    // YouTube-derived file. Exercises ExoPlayer / AVFoundation duration,
    // native decoder readiness and sample-accurate seeking beyond 2 minutes.
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/breezze-full-length-audio-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(
      _testStereoWav(sampleRate: 16000, seconds: 125),
      flush: true,
    );
    final engine = JustAudioEngineAdapter();
    final container = ProviderContainer();
    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('Full-length native audio acceptance')),
    ));
    try {
      await tester.runAsync(() => player.playTrack(
        trackId: 'device:full-length-native-qa',
        title: 'Breezze full-length original test tone',
        artist: 'Synthetic, rights-owned QA',
        localFilePath: file.path,
        duration: const Duration(seconds: 125),
      ).timeout(const Duration(seconds: 35)));
      expect(player.state.playbackState, PlaybackState.playing);
      expect(engine.duration, greaterThan(const Duration(minutes: 2)),
        reason: 'Native decoder must recognize a full-length audio file');
      await player.seekTo(const Duration(seconds: 100));
      expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 99)),
        reason: 'A far seek must reach the actual decoder, not only the UI');
      await player.pause();
      expect(player.state.playbackState, PlaybackState.paused);
      await player.resume();
      expect(player.state.playbackState, PlaybackState.playing);
      await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 800),
      ));
      expect(engine.position, greaterThan(const Duration(seconds: 100)),
        reason: 'Native decoder clock must progress after resuming a far seek');
    } finally {
      await player.stop();
      container.dispose();
      await engine.dispose();
      if (await file.exists()) await file.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('actual platform audio engine decodes app-owned PCM and obeys controls',
      (tester) async {
    // This is real ExoPlayer/AVFoundation decoding, not a fake engine. A
    // synthetic QA tone does not require a third-party music entitlement.
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/breezze-native-pcm-${DateTime.now().microsecondsSinceEpoch}.wav');
    await file.writeAsBytes(_testStereoWav(), flush: true);
    final engine = JustAudioEngineAdapter();
    final container = ProviderContainer();
    final player = container.read(playerControllerProvider.notifier);
    player.attachEngine(engine);
    try {
      await player.playTrack(
        trackId: 'device:native-pcm-acceptance',
        title: 'Breezze native QA PCM',
        artist: 'Synthetic test source',
        localFilePath: file.path,
        duration: const Duration(seconds: 3),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(engine.duration, greaterThan(Duration.zero));
      expect(player.state.playbackState, PlaybackState.playing);

      await player.seekTo(const Duration(milliseconds: 900));
      expect(player.state.position.inMilliseconds, greaterThanOrEqualTo(900));
      await player.pause();
      expect(player.state.playbackState, PlaybackState.paused);

      final media = AudioServiceBridge(container);
      await media.update(
        title: 'Breezze native QA PCM',
        artist: 'Synthetic test source',
        playing: false,
      );
      expect(media.mediaItem.value?.id, 'device:native-pcm-acceptance');
      await media.play();
      expect(player.state.playbackState, PlaybackState.playing);
      await media.stop();
      expect(player.state.playbackState, PlaybackState.idle);
    } finally {
      await player.stop();
      container.dispose();
      await engine.dispose();
      if (await file.exists()) await file.delete();
    }
  });



}
