import 'dart:io';

import 'package:breezze/core/audio/youtube_audio_native.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(args.single)) {
    throw ArgumentError('Pass one public YouTube video ID.');
  }
  final url = await resolveYouTubeAudio(args.single);
  if (url == null) {
    throw StateError('Provider returned no usable audio manifest on this network.');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(url);
    request.headers.set('Range', 'bytes=0-65535');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (![200, 206].contains(response.statusCode)) {
      throw StateError('Audio CDN returned HTTP ${response.statusCode}.');
    }
    final bytes = await response.first.timeout(const Duration(seconds: 8));
    if (bytes.isEmpty) throw StateError('Empty audio response.');
    stdout.writeln('Received audio bytes for the selected video.');
  } finally {
    client.close(force: true);
  }
}
