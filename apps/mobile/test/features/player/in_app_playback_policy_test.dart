import 'package:breezze/core/audio/playback_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('third-party catalog metadata never enters Breezze native audio queue', () {
    for (final id in [
      'bz:spotify:4uLU6hMCjMI75M1A2tKUQC',
      'bz:deezer:3135556',
      'bz:musicbrainz:123e4567-e89b-12d3-a456-426614174000',
      'bz:youtube_music:dQw4w9WgXcQ',
      'bzv:dQw4w9WgXcQ',
    ]) {
      expect(isMetadataOnlyTrackId(id), isTrue, reason: id);
      expect(canQueueTrackId(id), isFalse, reason: id);
      expect(canRequestOfflineDownload(id), isFalse, reason: id);
    }
  });

  test('only explicitly identified previews have provider-native queue access', () {
    expect(isDeezerPreview('bz:deezer_preview:3135556'), isTrue);
    expect(canQueueTrackId('bz:deezer_preview:3135556'), isTrue);
    expect(canRequestOfflineDownload('bz:deezer_preview:3135556'), isFalse);
    expect(isDeezerPreview('bz:deezer_preview:bogus'), isFalse);
  });

  test('owned media remains eligible for authorization by the backend', () {
    expect(canQueueTrackId('licensed-track-1'), isTrue);
    expect(canRequestOfflineDownload('licensed-track-1'), isTrue);
  });
}
