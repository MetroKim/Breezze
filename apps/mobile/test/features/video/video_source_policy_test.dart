import 'package:breezze/features/video/video_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final trustedOrigin = Uri.parse('https://media.breezze.app');
  final now = DateTime.utc(2026, 11, 27, 11, 0);
  const id = '123e4567-e89b-42d3-a456-426614174000';
  final expires = now.millisecondsSinceEpoch + const Duration(minutes: 10).inMilliseconds;
  final signature = 'A' * 43;

  Uri videoGrant({
    String origin = 'https://media.breezze.app',
    String? path,
    String? query,
  }) => Uri.parse(
    '$origin${path ?? '/video/$id/stream'}'
    '?${query ?? 'e=$expires&s=$signature'}',
  );

  test('only exact Breezze CDN origin with valid signed stream lease is accepted', () {
    expect(
      isValidBreezzeVideoStreamUrl(
        videoGrant(), trustedOrigin: trustedOrigin, nowUtc: now,
      ),
      isTrue,
    );
    expect(
      isValidBreezzeVideoStreamUrl(
        videoGrant(), trustedOrigin: Uri.parse('https://media.breezze.app/'),
        nowUtc: now,
      ),
      isTrue,
    );
    expect(
      isValidBreezzeVideoStreamUrl(
        videoGrant(), trustedOrigin: Uri.parse('http://media.breezze.app'),
        nowUtc: now,
      ),
      isFalse,
    );
  });

  test('rejects attacker, typo, userinfo and fragment URL variants', () {
    for (final origin in [
      'https://evil.example',
      'https://media.breezze.app.evil.example',
      'http://media.breezze.app',
      'https://user:secret@media.breezze.app',
      'https://media.breezze.app:8443',
    ]) {
      expect(isValidBreezzeVideoStreamUrl(
        videoGrant(origin: origin), trustedOrigin: trustedOrigin, nowUtc: now,
      ), isFalse, reason: origin);
    }
    expect(isValidBreezzeVideoStreamUrl(
      Uri.parse('${videoGrant()}#token'), trustedOrigin: trustedOrigin, nowUtc: now,
    ), isFalse);
  });

  test('rejects wrong purpose, malformed asset IDs, and path smuggling', () {
    for (final path in [
      '/video/$id/download',
      '/video/aaaaaaaaaaa/stream',
      '/video/../../audio/stream',
      '/audio/$id/stream',
      '/video/$id/stream/extra',
    ]) {
      expect(isValidBreezzeVideoStreamUrl(
        videoGrant(path: path), trustedOrigin: trustedOrigin, nowUtc: now,
      ), isFalse, reason: path);
    }
  });

  test('rejects missing, duplicate, expired, oversized and forged-format grants', () {
    for (final query in [
      'e=$expires',
      'e=$expires&s=invalid',
      'e=$expires&s=$signature&extra=x',
      'e=$expires&s=$signature&s=$signature',
      'e=garbage&s=$signature',
      'e=${now.millisecondsSinceEpoch - 1}&s=$signature',
      'e=${now.millisecondsSinceEpoch + const Duration(hours: 4).inMilliseconds}&s=$signature',
    ]) {
      expect(isValidBreezzeVideoStreamUrl(
        videoGrant(query: query), trustedOrigin: trustedOrigin, nowUtc: now,
      ), isFalse, reason: query);
    }
  });

  test('seek is clamped and never moves past recording limits', () {
    const length = Duration(minutes: 2);
    expect(videoSeekTarget(const Duration(seconds: 8),
      const Duration(seconds: -10), length), Duration.zero);
    expect(videoSeekTarget(const Duration(seconds: 32),
      const Duration(seconds: 10), length), const Duration(seconds: 42));
    expect(videoSeekTarget(const Duration(seconds: 115),
      const Duration(seconds: 10), length), length);
    expect(videoSeekTarget(const Duration(seconds: 50),
      const Duration(seconds: -10), Duration.zero), Duration.zero);
  });

  test('video time labels support short and long videos', () {
    expect(videoClock(Duration.zero), '0:00');
    expect(videoClock(const Duration(seconds: 75)), '1:15');
    expect(videoClock(const Duration(hours: 1, minutes: 4, seconds: 5)), '1:04:05');
    expect(videoClock(const Duration(seconds: -20)), '0:00');
  });
}
