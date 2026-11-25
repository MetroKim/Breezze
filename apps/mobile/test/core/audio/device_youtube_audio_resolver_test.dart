import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/device_youtube_audio_resolver.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:breezze/core/audio/youtube_stream_probe.dart';

void main() {
  const id = 'bz:youtube_music:abcdefghijk';
  final now = DateTime.utc(2026, 11, 25);
  final deadline = now.add(const Duration(minutes: 5))
      .millisecondsSinceEpoch ~/ 1000;
  DeviceYouTubeAudioCandidate candidate(String url, {
    int bitrate = 128000, String container = 'mp4', String codec = 'mp4a.40.2',
  }) =>
      DeviceYouTubeAudioCandidate(
        url: Uri.parse(url), bitrate: bitrate,
        audioCodec: codec, container: container,
      );

  test('picks highest bitrate direct valid on-device audio stream', () {
    final source = selectDeviceYouTubeAudio(id, [
      candidate('https://rr1.googlevideo.com/videoplayback?expire=$deadline',
        bitrate: 64000),
      candidate('https://rr2.googlevideo.com/videoplayback?expire=$deadline',
        bitrate: 128000),
    ], nowUtc: now);
    expect(source?.streamUrl, contains('rr2.googlevideo.com'));
    expect(source?.codec, 'mp4a.40.2');
    expect(source?.sessionId, isNull);
    expect(source?.isLocal, isFalse);
    expect(source?.trackId, id);
  });

  test('iOS-compatible MP4/AAC selection ignores higher bitrate WebM/Opus', () {
    final streams = [
      candidate('https://rr1.googlevideo.com/videoplayback?expire=$deadline',
        bitrate: 128000),
      candidate('https://rr2.googlevideo.com/videoplayback?expire=$deadline',
        bitrate: 160000, container: 'webm', codec: 'opus'),
    ];
    final apple = selectDeviceYouTubeAudio(id, streams, nowUtc: now);
    expect(apple?.streamUrl, contains('rr1.googlevideo.com'));
    final android = selectDeviceYouTubeAudio(id, streams, nowUtc: now,
      supportedContainers: const {'mp4', 'webm'});
    expect(android?.streamUrl, contains('rr2.googlevideo.com'));
  });

  test('rejects mismatched codecs, unknown containers and extreme expirations', () {
    final good = 'https://rr1.googlevideo.com/videoplayback?expire=$deadline';
    for (final entry in [
      candidate(good, container: 'webm', codec: 'mp4a.40.2'),
      candidate(good, container: 'mp4', codec: 'opus'),
      candidate(good, container: 'flv'),
      candidate('https://rr1.googlevideo.com/video?expire=$deadline'),
      candidate('https://rr1.googlevideo.com/videoplayback?expire=999999999999999999999'),
    ]) {
      expect(selectDeviceYouTubeAudio(id, [entry], nowUtc: now,
        supportedContainers: const {'mp4', 'webm'}), isNull);
    }
  });

  test('blocks forged, expired, local and non-HTTPS media URLs', () {
    for (final url in [
      'http://rr1.googlevideo.com/videoplayback?expire=$deadline',
      'https://evilgooglevideo.com/videoplayback?expire=$deadline',
      'https://127.0.0.1/videoplayback?expire=$deadline',
      'https://user:pass@rr1.googlevideo.com/videoplayback?expire=$deadline',
      'https://rr1.googlevideo.com/videoplayback?expire=$deadline#fragment',
      'https://rr1.googlevideo.com/videoplayback',
      'https://rr1.googlevideo.com/videoplayback?expire=1',
    ]) {
      expect(selectDeviceYouTubeAudio(id, [candidate(url)], nowUtc: now),
          isNull, reason: url);
    }
  });

  test('cannot attach external audio to a different track identity', () {
    expect(selectDeviceYouTubeAudio(
      'bz:deezer:123',
      [candidate('https://rr1.googlevideo.com/videoplayback?expire=$deadline')],
      nowUtc: now,
    ), isNull);
    expect(selectDeviceYouTubeAudio(
      'bz:youtube_music:invalid',
      [candidate('https://rr1.googlevideo.com/videoplayback?expire=$deadline')],
      nowUtc: now,
    ), isNull);
  });
  test('falls back to the next source when the preferred media URL refuses', () async {
    final attempts = <String>[];
    final diagnostics = <String>[];
    final available = [
      candidate('https://rr1.googlevideo.com/videoplayback?expire=$deadline',
        bitrate: 160000, container: 'webm', codec: 'opus'),
      candidate('https://rr2.googlevideo.com/videoplayback?expire=$deadline',
        bitrate: 128000),
    ];
    final chosen = await findReachableYouTubeAudio(
      id, available, nowUtc: now, supportedContainers: const {'webm', 'mp4'},
      diagnostic: diagnostics.add,
      probe: (url) async {
        attempts.add(url.host);
        return url.host == 'rr2.googlevideo.com';
      },
    );
    expect(attempts, ['rr1.googlevideo.com', 'rr2.googlevideo.com']);
    expect(chosen?.streamUrl, contains('rr2.googlevideo.com'));
    expect(diagnostics, ['AUDIO_CANDIDATES_2',
      'STREAM_PROBE_REJECTED', 'STREAM_PROBE_OK']);
  });

  test('rejects invalid URLs without any network calls and bounds fallbacks', () async {
    var attempts = 0;
    final choices = [
      candidate('https://localhost/videoplayback?expire=$deadline', bitrate: 512000),
      for (var i = 1; i <= 5; i++)
        candidate('https://rr$i.googlevideo.com/videoplayback?expire=$deadline',
          bitrate: 256000 - (i * 10000)),
    ];
    final chosen = await findReachableYouTubeAudio(
      id, choices, nowUtc: now, maxProbeAttempts: 2,
      probe: (_) async {
        attempts++;
        throw StateError('network blocked');
      },
    );
    expect(chosen, isNull);
    expect(attempts, 2);
  });

  test('HTTP probe requests just the first byte without redirects or storing media', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.headers['Range'], 'bytes=0-0');
      expect(request.followRedirects, isFalse);
      return http.Response('x', 206, headers: {
        'content-type': 'audio/mp4',
        'content-range': 'bytes 0-0/100000',
      });
    });
    addTearDown(client.close);
    expect(await probeYouTubeAudioStream(
      Uri.parse('https://rr1.googlevideo.com/videoplayback?expire=$deadline'),
      client: client,
    ), isTrue);
    expect(requests, 1);
  });

  test('HTTP probe rejects failed, redirected, HTML and untrusted responses', () async {
    for (final status in [302, 403, 429, 500]) {
      final client = MockClient((_) async => http.Response('', status,
        headers: {'content-type': 'audio/mp4'}));
      expect(await probeYouTubeAudioStream(
        Uri.parse('https://rr1.googlevideo.com/videoplayback?expire=$deadline'),
        client: client,
      ), isFalse);
      client.close();
    }
    final html = MockClient((_) async => http.Response('<html>', 200,
      headers: {'content-type': 'text/html'}));
    expect(await probeYouTubeAudioStream(
      Uri.parse('https://rr1.googlevideo.com/videoplayback?expire=$deadline'),
      client: html,
    ), isFalse);
    html.close();
    var called = false;
    final blocked = MockClient((_) async {
      called = true;
      return http.Response('x', 200);
    });
    expect(await probeYouTubeAudioStream(
      Uri.parse('https://example.org/videoplayback'), client: blocked,
    ), isFalse);
    expect(called, isFalse);
    blocked.close();
  });

}
