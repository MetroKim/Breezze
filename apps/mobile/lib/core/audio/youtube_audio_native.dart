import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolve on the listening device so the CDN sees the same client IP.
Future<Uri?> resolveYouTubeAudio(String videoId) async {
  final client = YoutubeExplode();
  try {
    final manifest = await client.videos.streams.getManifest(videoId,
        ytClients: [YoutubeApiClient.androidSdkless]).timeout(const Duration(seconds: 10));
    final formats = manifest.audioOnly.where((s) => s.url.scheme == 'https' &&
        s.url.host.endsWith('.googlevideo.com')).toList();
    // AAC in MP4 plays on both AVFoundation and ExoPlayer.
    final aac = formats.where((s) => s.container.name == 'mp4');
    final candidates = aac.isEmpty ? formats : aac;
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) =>
        a.bitrate.bitsPerSecond >= b.bitrate.bitsPerSecond ? a : b).url;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
