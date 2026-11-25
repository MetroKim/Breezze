import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/remote_audio_grant.dart';

void main() {
  final now = DateTime.utc(2026, 11, 25, 16);
  final validUntil = now.add(const Duration(minutes: 2));

  test('accepts a bounded signed HTTPS audio grant', () {
    expect(isUsableRemoteAudioGrant(
      'https://media.licensed.example/stream?signature=secret',
      validUntil,
      nowUtc: now,
    ), isTrue);
  });

  test('never accepts local, insecure or credential-bearing media origins', () {
    for (final url in [
      'http://media.licensed.example/stream',
      'https://user:pass@media.licensed.example/stream',
      'https://127.0.0.1/stream',
      'https://[::1]/stream',
      'https://localhost/stream',
      'https://node.internal/stream',
      'https://media.licensed.example/stream#fragment',
      'not a url',
    ]) {
      expect(isUsableRemoteAudioGrant(url, validUntil, nowUtc: now), isFalse,
          reason: url);
    }
  });

  test('nearly expired and expired URLs must be re-resolved', () {
    for (final remaining in [
      const Duration(seconds: -1),
      Duration.zero,
      minimumRemoteGrantRemaining,
    ]) {
      expect(isUsableRemoteAudioGrant(
        'https://media.licensed.example/stream',
        now.add(remaining),
        nowUtc: now,
      ), isFalse);
    }
    expect(isUsableRemoteAudioGrant(
      'https://media.licensed.example/stream',
      now.add(minimumRemoteGrantRemaining + const Duration(seconds: 1)),
      nowUtc: now,
    ), isTrue);
  });
}
