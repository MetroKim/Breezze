import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  group('Breezze provider action policy', () {
    test('removed providers and discovery-only IDs never enter the native audio queue', () {
      for (final id in [
        'bz:youtube_music:abc',
        'bz:deezer:123',
        'bz:soundcloud:456',
        'bz:audius:V66vyPP',
        'bz:jamendo:track-123',
        'bz:apple_catalog:789',
        'bzv:dQw4w9WgXcQ',
        '',
      ]) {
        expect(canQueueTrackId(id), isFalse, reason: id);
      }
    });

    test('only canonical rights-cleared tracks can queue natively', () {
      expect(canQueueTrackId('catalog-uuid'), isTrue);
      expect(canQueueTrackId('bz:deezer_preview:42'), isFalse);
      expect(canQueueTrackId('bz:deezer_preview:nope'), isFalse);
      expect(canRequestOfflineDownload('bz:deezer_preview:42'), isFalse);
    });

    test('fallback requires an unambiguous preview of the selected recording', () {
      const duration = Duration(seconds: 210);
      final row = {'title': 'Song', 'artist': 'Artist', 'durationSec': 212,
          'providerTrackId': '42', 'previewUrl': 'https://example.org/test.mp3'};
      expect(matchingDeezerPreview([row], 'Song', 'Artist', duration), '42');
      expect(matchingDeezerPreview([row, {...row, 'providerTrackId': '43'}], 'Song', 'Artist', duration), isNull);
      expect(matchingDeezerPreview([row], 'Song (Live)', 'Artist', duration), isNull);
      expect(matchingDeezerPreview([row], 'Song', 'Artist', const Duration(seconds: 120)), isNull);
    });

    test('removed providers, metadata and video IDs never request offline downloads', () {
      expect(canRequestOfflineDownload('bz:audius:V66vyPP'), isFalse);
      expect(canRequestOfflineDownload('bz:jamendo:123'), isFalse);
      expect(canRequestOfflineDownload('bz:deezer:123'), isFalse);
      expect(canRequestOfflineDownload('bzv:dQw4w9WgXcQ'), isFalse);
      expect(canRequestOfflineDownload('catalog-uuid'), isTrue);
    });

    test('search offers official video playback without native YouTube queueing', () {
      const youtube = 'bz:youtube_music:dQw4w9WgXcQ';
      expect(canOfferPlaybackAction(youtube), isTrue);
      expect(canQueueTrackId(youtube), isFalse);
      expect(canOfferPlaybackAction('bzv:dQw4w9WgXcQ'), isTrue);
      expect(canOfferPlaybackAction('bzv:not-valid'), isFalse);
      expect(canOfferPlaybackAction('bz:deezer:123'), isFalse);
      expect(canOfferPlaybackAction('bz:deezer:123', hasPreview: true), isFalse);
      expect(canOfferPlaybackAction('bz:deezer:invalid', hasPreview: true), isFalse);
      expect(canOfferPlaybackAction('bz:deezer_preview:123'), isFalse);
      expect(canOfferPlaybackAction('bz:apple_catalog:123'), isFalse);
      expect(canOfferPlaybackAction('bz:spotify:4iV5W9uYEdYUVa79Axb7Rh'), isTrue);
      expect(canQueueTrackId('bz:spotify:4iV5W9uYEdYUVa79Axb7Rh'), isFalse);
      expect(canOfferPlaybackAction(''), isFalse);
    });

    test('YouTube music IDs remain official-video-only, never native Deezer audio queue', () {
      const id = 'bz:youtube_music:dQw4w9WgXcQ';
      expect(isYouTubeSongId(id), isTrue);
      expect(canQueueTrackId(id), isFalse);
      expect(canRequestOfflineDownload(id), isFalse);
      expect(isYouTubeSongId('bz:youtube_music:invalid'), isFalse);
      expect(isYouTubeSongId('bz:deezer:dQw4w9WgXcQ'), isFalse);
    });
  });
}
