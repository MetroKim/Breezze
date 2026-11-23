import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../player/player_controller.dart';
import 'official_music_video_screen.dart';

/// Opens YouTube's visible player without putting a metadata ID in the native queue.
Future<void> openYouTubePlayer({
  required BuildContext context,
  required WidgetRef ref,
  required String videoId,
  required String title,
  required String artist,
  String? artworkUrl,
}) async {
  await ref.read(playerControllerProvider.notifier).pause();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => OfficialMusicVideoScreen(
      videoId: videoId,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
    ),
  ));
}
