import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/spotify_playback_handoff.dart';
import '../../core/audio/deezer_playback_handoff.dart';
import 'player_controller.dart';

/// Music-provider playback outside Breezze's native media engine.
///
/// Spotify and Deezer handle their own licensed full-track audio, user
/// subscriptions and transport. Breezze neither extracts their bytes nor
/// caches provider audio for offline use.
class OfficialMusicPlayback {
  static bool canOpen(String trackId) =>
      SpotifyPlaybackHandoff.spotifyIdFromBreezze(trackId) != null ||
      DeezerPlaybackHandoff.deezerIdFromBreezze(trackId) != null;

  static String providerName(String trackId) =>
      SpotifyPlaybackHandoff.spotifyIdFromBreezze(trackId) != null
          ? 'Spotify'
          : DeezerPlaybackHandoff.deezerIdFromBreezze(trackId) != null
              ? 'Deezer'
              : 'Music provider';

  /// Returns false on unavailable links; callers show the actionable UI.
  /// Opening a link alone cannot prove that a full track started playing.
  static Future<bool> open(WidgetRef ref, String trackId) async {
    final spotifyId = SpotifyPlaybackHandoff.spotifyIdFromBreezze(trackId);
    final deezerId = DeezerPlaybackHandoff.deezerIdFromBreezze(trackId);
    if (spotifyId == null && deezerId == null) return false;
    await ref.read(playerControllerProvider.notifier).stop();
    if (spotifyId != null) {
      return SpotifyPlaybackHandoff.openTrack(spotifyId);
    }
    return DeezerPlaybackHandoff.openTrack(deezerId!);
  }
}
