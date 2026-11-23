import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/bz_brand_icons.dart';
import '../player/now_playing_screen.dart';
import '../player/player_controller.dart';
import 'open_goldberg.dart';

class FreeMusicScreen extends ConsumerWidget {
  const FreeMusicScreen({super.key});

  void _play(BuildContext context, WidgetRef ref, List<TrackInfo> queue, int index, String source) {
    unawaited(ref.read(playerControllerProvider.notifier).playTrack(
      trackId: queue[index].id, queue: queue, startIndex: index,
      origin: 'free_music', sourceContext: source,
    ));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NowPlayingScreen()));
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
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
      _play(context, ref, tracks, 0, 'Device files');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open those files. Choose an audio file and try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = List.generate(OpenGoldberg.length, (index) => TrackInfo(
      id: OpenGoldberg.id(index), title: OpenGoldberg.title(index), artist: OpenGoldberg.artist,
    ));
    return Scaffold(
      appBar: AppBar(title: const Text('Listen free')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(onPressed: () => _pick(context, ref),
            icon: const BzSvgIcon(name: 'music-note'), label: const Text('Play files from this device')),
        const SizedBox(height: 24),
        Text(OpenGoldberg.album, style: Theme.of(context).textTheme.headlineSmall),
        const Text('Bach · Kimiko Ishizaka, piano'),
        const SizedBox(height: 12),
        for (final (index, track) in tracks.indexed)
          ListTile(leading: Text('${index + 1}'), title: Text(track.title!),
            trailing: const BzSvgIcon(name: 'play', size: 18),
            onTap: () => _play(context, ref, tracks, index, OpenGoldberg.album)),
      ])),
    );
  }
}
