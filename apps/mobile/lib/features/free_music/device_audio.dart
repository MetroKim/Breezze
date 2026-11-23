import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../player/now_playing_screen.dart';
import '../player/player_controller.dart';

Future<void> pickDeviceAudio(BuildContext context, WidgetRef ref) async {
    const audio = XTypeGroup(label: 'Audio', extensions: ['mp3','m4a','aac','flac','wav','ogg'],
        mimeTypes: ['audio/*'], uniformTypeIdentifiers: ['public.audio']);
    try {
      final files = await openFiles(acceptedTypeGroups: [audio]);
      if (!context.mounted || files.isEmpty) return;
      final batch = DateTime.now().microsecondsSinceEpoch;
      final tracks = [
        for (final (index, file) in files.indexed)
          TrackInfo(id: 'device:$batch:$index', title: file.name,
              artist: 'On this device', localFilePath: file.path),
      ];
      unawaited(ref.read(playerControllerProvider.notifier).playTrack(
        trackId: tracks.first.id, queue: tracks, startIndex: 0,
        origin: 'device', sourceContext: 'Device files',
      ));
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NowPlayingScreen()));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open those files. Choose an audio file and try again.')),
        );
      }
    }
  }
