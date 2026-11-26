import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/playback_source_policy.dart';

/// Opens provider-owned full tracks in their official app or website.
///
/// This is an external handoff, not a license to stream, download, or cache
/// provider music inside Breezze. The WidgetRef argument is preserved for
/// callers that already share a common playback routing API.
class OfficialMusicPlayback {
  const OfficialMusicPlayback._();

  static Uri? urlFor(String trackId) {
    if (isSpotifyTrackId(trackId)) {
      return Uri.https(
        'open.spotify.com',
        '/track/${trackId.substring('bz:spotify:'.length)}',
      );
    }
    if (isDeezerTrackId(trackId)) {
      return Uri.https(
        'www.deezer.com',
        '/track/${trackId.substring('bz:deezer:'.length)}',
      );
    }
    return null;
  }

  static bool canOpen(String trackId) => urlFor(trackId) != null;

  static String providerName(String trackId) {
    if (isSpotifyTrackId(trackId)) return 'Spotify';
    if (isDeezerTrackId(trackId)) return 'Deezer';
    return 'the music provider';
  }

  static Future<bool> open(WidgetRef ref, String trackId) async {
    final url = urlFor(trackId);
    if (url == null) return false;
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
