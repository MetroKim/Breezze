import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  group('Breezze provider action policy', () {
    test('discovery-only IDs never enter the native audio queue', () {
      for (final id in [
        'bz:youtube_music:abc',
        'bz:deezer:123',
        'bz:soundcloud:456',
        'bz:audius:retired',
        'bz:apple_catalog:789',
        'bzv:dQw4w9WgXcQ',
        '',
      ]) {
        expect(canQueueTrackId(id), isFalse, reason: id);
      }
    });

    test('local or backend tracks and approved Jamendo can request playback', () {
      expect(canQueueTrackId('catalog-uuid'), isTrue);
      expect(canQueueTrackId('bz:deezer_preview:42'), isTrue);
      expect(canQueueTrackId('bz:deezer_preview:nope'), isFalse);
      expect(canRequestOfflineDownload('bz:deezer_preview:42'), isFalse);
      expect(canQueueTrackId('bz:jamendo:track-123'), isTrue);
      expect(isMetadataOnlyTrackId('bz:jamendo:track-123'), isFalse);
    });

    test('metadata and embedded videos never request offline downloads', () {
      expect(canRequestOfflineDownload('bz:jamendo:123'), isFalse);
      expect(canRequestOfflineDownload('bz:deezer:123'), isFalse);
      expect(canRequestOfflineDownload('bzv:dQw4w9WgXcQ'), isFalse);
      expect(canRequestOfflineDownload('catalog-uuid'), isTrue);
    });

    test('YouTube song IDs can request native playback', () {
      const id = 'bz:youtube_music:dQw4w9WgXcQ';
      expect(isYouTubeSongId(id), isTrue);
      expect(canQueueTrackId(id), isTrue);
      expect(canRequestOfflineDownload(id), isFalse);
      expect(isYouTubeSongId('bz:youtube_music:invalid'), isFalse);
      expect(isYouTubeSongId('bz:deezer:dQw4w9WgXcQ'), isFalse);
    });
  });
}
