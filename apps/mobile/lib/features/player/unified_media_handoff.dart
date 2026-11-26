import 'player_controller.dart' show TrackInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/audio/playback_source_policy.dart';
import '../video/open_youtube_player.dart';
import '../video/official_youtube_queue_policy.dart';

/// YouTube is video-only in Breezze. No native audio stream, no extraction,
/// no offline download, and no hidden player, even if the metadata resembles
/// a music recording.
enum BreezzePlaybackRoute { officialYouTubeVideo, superseded }

List<TrackInfo> youtubeMusicQueue(Iterable<TrackInfo> candidates) {
  final seen = <String>{};
  return [
    for (final track in candidates)
      if (isYouTubeSongId(track.id) && seen.add(track.id)) track,
  ];
}

/// Legacy entrypoint used by Search and Library; the method name is retained
/// for source compatibility, but it exclusively opens visible official video.
/// Spotify music takes a separate Spotify app playback route.
Future<BreezzePlaybackRoute> playYoutubeMusicWithVideoFallback({
  required BuildContext context,
  required WidgetRef ref,
  required TrackInfo selected,
  required Iterable<TrackInfo> candidates,
  required String origin,
  required String sourceContext,
  bool openNowPlaying = false,
}) async {
  if (!isYouTubeSongId(selected.id)) {
    throw ArgumentError.value(
      selected.id, 'selected.id', 'Not a YouTube video',
    );
  }
  final tracks = youtubeMusicQueue(candidates);
  if (!tracks.any((track) => track.id == selected.id)) {
    return BreezzePlaybackRoute.superseded;
  }
  if (!context.mounted) return BreezzePlaybackRoute.superseded;

  await openYouTubePlayer(
    context: context,
    ref: ref,
    videoId: selected.id.substring('bz:youtube_music:'.length),
    title: selected.title ?? 'Unknown title',
    artist: selected.artist ?? 'Unknown artist',
    artworkUrl: selected.artworkUrl,
    foregroundQueue: [
      for (final track in tracks)
        OfficialYouTubeQueueEntry(
          videoId: track.id.substring('bz:youtube_music:'.length),
          title: track.title ?? 'Unknown title',
          artist: track.artist ?? 'Unknown artist',
          artworkUrl: track.artworkUrl,
        ),
    ],
  );
  return BreezzePlaybackRoute.officialYouTubeVideo;
}
