import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// iOS AVFoundation native decoder acceptance with a CI-generated ORIGINAL video.
/// This does not use any YouTube, Spotify or protected commercial recording.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS AVFoundation MP4 decodes, advances, seeks, pauses and replays',
      (tester) async {
    expect(defaultTargetPlatform, TargetPlatform.iOS);
    const encoded = String.fromEnvironment('BREEZZE_VIDEO_QA_BASE64');
    expect(encoded, isNotEmpty,
        reason: 'Original MP4 fixture must be supplied by the QA workflow');

    final folder = await getTemporaryDirectory();
    final file = File('${folder.path}/breezze-video-decoder-acceptance.mp4');
    await file.writeAsBytes(base64Decode(encoded), flush: true);

    final controller = VideoPlayerController.file(file);
    addTearDown(() async {
      await controller.dispose();
      if (await file.exists()) await file.delete();
    });

    await tester.runAsync(() async {
      await controller.initialize().timeout(const Duration(seconds: 30));
    });
    expect(controller.value.isInitialized, isTrue);
    expect(controller.value.hasError, isFalse);
    expect(controller.value.duration, greaterThan(const Duration(seconds: 2)));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 90,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 900));
    });
    expect(controller.value.isPlaying, isTrue);
    expect(controller.value.position,
      greaterThan(const Duration(milliseconds: 100)),
      reason: 'The AVFoundation MP4 decoder must advance its video clock');

    await tester.runAsync(() async {
      await controller.pause();
      await controller.seekTo(const Duration(seconds: 2));
    });
    expect(controller.value.isPlaying, isFalse);
    expect(controller.value.position,
      greaterThanOrEqualTo(const Duration(milliseconds: 1800)));

    await tester.runAsync(() async {
      await controller.seekTo(Duration.zero);
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 450));
    });
    expect(controller.value.isPlaying, isTrue);
    expect(controller.value.position,
      greaterThan(Duration.zero),
      reason: 'Replay must restart actual native MP4 frames');

    await tester.runAsync(() async {
      await controller.pause();
      await controller.setLooping(true);
    });
    expect(controller.value.isLooping, isTrue);
    expect(controller.value.hasError, isFalse);
  });
}
