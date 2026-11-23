import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Queue preparation and a tap on the same song share one provider request.
final _pending = <(String, int), Future<Uri?>>{};

Future<Uri?> resolveYouTubeAudio(String videoId, {int ceilingKbps = 256}) {
  final key = (videoId, ceilingKbps);
  return _pending.putIfAbsent(key, () => _resolve(videoId, ceilingKbps)
      .whenComplete(() { _pending.remove(key); }));
}

/// Resolve on the listening device so the CDN sees the same client IP.
Future<Uri?> _resolve(String videoId, int ceilingKbps) async {
  final client = YoutubeExplode();
  try {
    final manifest = await client.videos.streams.getManifest(videoId,
        ytClients: [YoutubeApiClient.androidSdkless]).timeout(const Duration(seconds: 10));
    final formats = manifest.audioOnly.where((s) => s.url.scheme == 'https' &&
        s.url.host.endsWith('.googlevideo.com')).toList();
    // AAC in MP4 plays on both AVFoundation and ExoPlayer.
    formats.sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
    if (formats.isEmpty) return null;
    final withinLimit = formats.where((s) => s.bitrate.bitsPerSecond <= ceilingKbps * 1000);
    final aac = withinLimit.where((s) => s.container.name == 'mp4');
    return (aac.lastOrNull ?? withinLimit.lastOrNull ?? formats.first).url;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
