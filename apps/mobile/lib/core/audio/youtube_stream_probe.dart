import 'package:http/http.dart' as http';

/// Small, non-caching GET to ensure a transient audio URL is usable before
/// handing it to the native player. Range avoids transferring full song data.
/// The response body is cancelled immediately. No URL or response is logged.
Future<bool> probeYouTubeAudioStream(
  Uri url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final host = url.host.toLowerCase();
  if (url.scheme != 'https' ||
      !(host == 'googlevideo.com' || host.endsWith('.googlevideo.com')) ||
      url.path != '/videoplayback' ||
      url.userInfo.isNotEmpty ||
      url.hasFragment ||
      (url.hasPort && url.port != 443)) {
    return false;
  }

  final ownsClient = client == null;
  final activeClient = client ?? http.Client();
  try {
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers['Range'] = 'bytes=0-0';
    final response = await activeClient.send(request).timeout(timeout);
    final mime = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    // Audio-only manifest entries are authoritative on format. A CDN may
    // respond with application/octet-stream or omit Content-Type, but never
    // accept HTML, JSON, or a redirect as a playable media response.
    final mediaTypeAccepted = mime == null ||
        mime.startsWith('audio/') ||
        mime == 'application/octet-stream';
    final valid = (response.statusCode == 200 || response.statusCode == 206) &&
        mediaTypeAccepted &&
        response.headers['content-length'] != '0';
    final subscription = response.stream.listen((_) {}, cancelOnError: true);
    await subscription.cancel();
    return valid;
  } catch (_) {
    return false;
  } finally {
    if (ownsClient) activeClient.close();
  }
}
