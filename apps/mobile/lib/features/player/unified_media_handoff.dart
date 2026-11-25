import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/audio/playback_source_policy.dart';
import '../video/open_youtube_player.dart';
import '../video/official_youtube_queue_policy.dart';
import 'now_playing_screen.dart';
import 'player_controller.dart';

/// One source-aware handoff for Search and Library. A YouTube Music catalog
/// identity is metadata, not a full-track entitlement or a download license.
/// This coordinator never turns provider video URLs into audio-only URLs.
enum BreezzePlaybackRoute { nativeAudio, officialYouTubeVideo, superseded }

/// Validates IDs and deduplicates without reordering the user's queue.
List<TrackInfo> youtubeMusicQueue(Iterable<TrackInfo> candidates) {
  final seen = <String>{};
  return [
    for (final track in candidates)
      if (isYouTubeSongId(track.id) && seen.add(track.id)) track,
  ];
}

/// A native source is preferred only when the existing resolver successfully
/// establishes a real playable session. When it cannot, hand off to the
/// foreground official YouTube video player, never a hidden player.
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
    throw ArgumentError.value(selected.id, 'selected.id', 'Not a YouTube Music track');
  }
  final tracks = youtubeMusicQueue(candidates);
  final position = tracks.indexWhere((item) => item.id == selected.id);
  if (position < 0) {
    return BreezzePlaybackRoute.superseded;
  }
  final player = ref.read(playerControllerProvider.notifier);
  await player.playTrack(
    trackId: selected.id,
    queue: tracks,
    startIndex: position,
    origin: origin,
    sourceContext: sourceContext,
  );
  if (!context.mounted) return BreezzePlaybackRoute.superseded;
  final playback = ref.read(playerControllerProvider);
  // A newer user selection always wins; never open the previous recording
  // merely because its resolver failed after a later tap.
  if (playback.currentTrack?.id != selected.id) {
    return BreezzePlaybackRoute.superseded;
  }
  if (playback.playbackState == PlaybackState.playing) {
    if (openNowPlaying) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const NowPlayingScreen(),
      ));
    }
    return BreezzePlaybackRoute.nativeAudio;
  }
  await player.stop();
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
