import 'package:breezze_audio_contracts/audio_contracts.dart' show PlaybackState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_session.dart';
import '../player/now_playing_screen.dart';
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
  bool enableExperimentalNativeAudio = false,
}) async {
  // Only in explicitly built development clients, and only if the server
  // independently opted in. Normal YouTube video actions never take this path.
  if (enableExperimentalNativeAudio &&
      const bool.fromEnvironment('BREEZZE_YTMUSIC_AUDIO_EXPERIMENT')) {
    try {
      final candidate = await ref.read(authSessionProvider.notifier).api
          .ytMusicAudioCandidate(videoId);
      if (!context.mounted) return;
      if (candidate['kind'] == 'ok') {
        final value = candidate['value'];
        final source = value is Map ? value['candidate'] : null;
        if (source is Map && source['streamUrl'] is String &&
            source['mimeType'] is String &&
            (source['mimeType'] as String).startsWith('audio/')) {
          final id = 'bz:youtube_music:$videoId';
          final controller = ref.read(playerControllerProvider.notifier);
          await controller.playTrack(
            trackId: id,
            title: title,
            artist: artist,
            artworkUrl: artworkUrl,
            origin: 'youtube_music_dev_audio',
            sourceContext: 'Experimental YouTube Music audio',
          );
          if (!context.mounted) return;
          if (ref.read(playerControllerProvider).playbackState ==
              PlaybackState.playing) {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const NowPlayingScreen(),
            ));
            return;
          }
        }
      }
    } catch (_) {
      // An unavailable direct stream must not prevent ordinary foreground
      // YouTube viewing; this probe is never a production dependency.
    }
  }
  await openVideoSurface(context, (_) => OfficialMusicVideoScreen(
    videoId: videoId, title: title, artist: artist, artworkUrl: artworkUrl,
  ));
}

Future<void> openVideoSurface(BuildContext context, WidgetBuilder builder) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = container.read(playerControllerProvider.notifier);
  final previous = container.read(playerControllerProvider);
  if (previous.playbackState == PlaybackState.resolving ||
      previous.playbackState == PlaybackState.buffering ||
      previous.playbackState == PlaybackState.loading ||
      previous.playbackState == PlaybackState.transitioning) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audio is loading. Try the video again in a moment.')),
    );
    return;
  }
  final entry = controller.queue.current?.entryId;
  final resumeAudio = previous.playbackState == PlaybackState.playing;
  if (resumeAudio) await controller.pause();
  try {
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  } finally {
    if (context.mounted && resumeAudio && entry != null &&
        controller.queue.current?.entryId == entry &&
        container.read(playerControllerProvider).playbackState == PlaybackState.paused &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await controller.resume();
    }
  }
}
