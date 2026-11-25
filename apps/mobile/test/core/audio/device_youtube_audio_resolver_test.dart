import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/device_youtube_audio_resolver.dart';

void main() {
  const id = 'bz:youtube_music:abcdefghijk';
  final now = DateTime.utc(2026, 11, 25);
  final deadline = now.add(const Duration(minutes: 5))
      .millisecondsSinceEpoch ~/ 1000;
  DeviceYouTubeAudioCandidate candidate(String url, {int bitrate = 128000}) =>
      DeviceYouTubeAudioCandidate(
        url: Uri.parse(url), bitrate: bitrate, audioCodec: 'mp4a.40.2',
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
}
