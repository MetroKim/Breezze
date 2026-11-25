import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote signed sources refresh before their lease fully expires', () {
    PlayableSource grant(Duration remaining) => PlayableSource(
      trackId: 'licensed-recording',
      streamUrl: 'https://media.licensed.example/audio',
      expiresAtUtc: DateTime.now().toUtc().add(remaining),
    );

    expect(grant(const Duration(seconds: 10)).isExpired, isTrue);
    expect(grant(const Duration(minutes: 5)).isExpired, isFalse);
    expect(grant(const Duration(seconds: -1)).isExpired, isTrue);
  });

  test('local sources are not subject to remote signed URL expiry', () {
    final local = PlayableSource(
      trackId: 'device:1',
      streamUrl: '/music/song.flac',
      expiresAtUtc: DateTime.utc(2000),
      isLocal: true,
    );
    expect(local.isExpired, isFalse);
  });
}
