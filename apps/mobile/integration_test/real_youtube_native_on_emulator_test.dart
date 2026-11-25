import 'package:breezze/core/audio/audio_service_bridge.dart';
import 'package:breezze/core/audio/device_youtube_audio_resolver.dart';
import 'package:breezze/core/audio/just_audio_engine_adapter.dart';
import 'package:breezze/features/player/player_controller.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// Creative Commons Attribution 3.0 test video from Blender Foundation:
/// https://www.youtube.com/watch?v=aqz-KE-bpKQ
/// A real source is required: this test MUST NOT pass using mocks, previews,
/// or a local synthetic PCM fixture. No media is saved to disk.
const _creativeCommonsSample = TrackInfo(
  id: 'bz:youtube_music:aqz-KE-bpKQ',
  title: 'Big Buck Bunny',
  artist: 'Blender Foundation (CC BY 3.0)',
  duration: Duration(minutes: 9),
);

class _LiveDeviceYouTubeResolver implements PlaybackResolver {
  final List<String> stages = [];
  late final DeviceYouTubeAudioResolver resolver =
      DeviceYouTubeAudioResolver(diagnostic: stages.add);
  int requests = 0;

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    requests++;
    return resolver.resolve(track.id);
  }
}

/// Records only the native decoder failure type. No source URI is logged.
class _DiagnosticAudioEngine extends JustAudioEngineAdapter {
  String? prepareFailureType;

  @override
  Future<void> prepare(PlayableSource source) async {
    try {
      await super.prepare(source);
    } on Object catch (error) {
      prepareFailureType = error.runtimeType.toString();
      rethrow;
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'E2E native YouTube media: real manifest, HTTPS probe, decoder, '
    'audio progress, seek, pause and resume',
    (tester) async {
      final source = _LiveDeviceYouTubeResolver();
      final engine = _DiagnosticAudioEngine();
      final container = ProviderContainer(overrides: [
        playbackResolverProvider.overrideWithValue(source),
      ]);
      final player = container.read(playerControllerProvider.notifier);
      player.attachEngine(engine);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('Real native YouTube stream QA')),
      ));
      try {
        await tester.runAsync(() async {
          await player.playTrack(
            trackId: _creativeCommonsSample.id,
            queue: const [_creativeCommonsSample],
            origin: 'native-youtube-acceptance',
          ).timeout(const Duration(seconds: 55));
        });

        expect(source.requests, 1,
          reason: 'The real on-device manifest resolver must be invoked');
        expect(player.state.playbackState, PlaybackState.playing,
          reason: 'Real native media did not start. Safe stage diagnostics: '
              '${source.stages.join(" > ")}; '
              'native_prepare_failure=${engine.prepareFailureType ?? "none"}. '
              'No signed URLs or provider tokens are logged.');
        expect(engine.duration, greaterThan(const Duration(minutes: 2)),
          reason: 'The native engine must decode a real full-length track');

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(seconds: 2));
        });
        expect(engine.position, greaterThan(const Duration(milliseconds: 250)),
          reason: 'Actual audio decoder clock must advance beyond start');

        final bridge = AudioServiceBridge(container);
        await bridge.update(
          title: _creativeCommonsSample.title!,
          artist: _creativeCommonsSample.artist!,
          playing: true,
        );
        expect(bridge.mediaItem.value?.id, _creativeCommonsSample.id);
        await bridge.pause();
        expect(player.state.playbackState, PlaybackState.paused);
        await bridge.seek(const Duration(seconds: 12));
        expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 11)));
        await bridge.play();
        expect(player.state.playbackState, PlaybackState.playing);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        });
        expect(engine.position, greaterThan(const Duration(seconds: 12)));
        await bridge.stop();
        expect(player.state.playbackState, PlaybackState.idle);
      } finally {
        await player.stop();
        container.dispose();
        await engine.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
