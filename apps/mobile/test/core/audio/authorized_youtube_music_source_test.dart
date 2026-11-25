import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/authorized_youtube_music_source.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 25);
  const id = 'bz:youtube_music:abcdefghijk';
  Map<String, dynamic> grant(String url, {Duration lifetime = const Duration(minutes: 5)}) => {
    'id': 'session-123',
    'playback': {
      'streamUrl': url,
      'expiresAt': now.add(lifetime).toIso8601String(),
      'codec': 'aac',
    },
  };

  test('authorized full recording can play in native engine', () {
    final source = authorizedYouTubeMusicPlayback(
      id, grant('https://media.breezze.example/audio/master/AAC_256?e=1&s=signature'),
      nowUtc: now,
    );
    expect(source?.trackId, id);
    expect(source?.sessionId, 'session-123');
    expect(source?.codec, 'aac');
    expect(source?.isLocal, false);
    expect(canRequestOfflineDownload(id), false);
  });

  test('metadata, bad streams and expiring grants never become playable', () {
    expect(authorizedYouTubeMusicPlayback(id, {'kind': 'ok'}, nowUtc: now), isNull);
    expect(authorizedYouTubeMusicPlayback('bzv:abcdefghijk',
      grant('https://media.breezze.example/audio/master'), nowUtc: now), isNull);
    for (final url in [
      'http://media.breezze.example/audio/master',
      'https://127.0.0.1/audio/master',
      'https://localhost/audio/master',
      'https://user:pass@media.breezze.example/audio/master',
      'https://media.breezze.example/audio/master#fragment',
    ]) {
      expect(authorizedYouTubeMusicPlayback(id, grant(url), nowUtc: now), isNull);
    }
    expect(authorizedYouTubeMusicPlayback(id, grant(
      'https://media.breezze.example/audio/master',
      lifetime: const Duration(seconds: 10),
    ), nowUtc: now), isNull);
  });
}
