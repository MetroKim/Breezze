import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/auth/youtube_music_session.dart';

void main() {
  test('prefers the primary YouTube signing cookie', () {
    expect(
      youtubeMusicSigningSecret({
        '__Secure-3PAPISID': 'fallback',
        'SAPISID': 'primary',
      }),
      'primary',
    );
  });

  test('builds deterministic SAPISIDHASH authorization', () {
    expect(
      youtubeMusicAuthorization('secret', unixSeconds: 1700000000),
      'SAPISIDHASH 1700000000_d2a0deeb95ea263a68778d9e9ac8840dce59d800',
    );
  });

  test('cookie header is stable and excludes empty values', () {
    expect(
      youtubeMusicCookieHeader({'SID': 'two', 'SAPISID': 'one', 'empty': ''}),
      'SAPISID=one; SID=two',
    );
  });
}
