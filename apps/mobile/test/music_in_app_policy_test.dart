import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

/// Breezze uses one in-app audio UI; never redirects songs to Spotify or
/// Deezer applications and never treats discovery metadata as audio.
void main() {
  const spotify = 'bz:spotify:4iV5W9uYEdYUVa79Axb7Rh';
  const deezer = 'bz:deezer:3135556';
  const preview = 'bz:deezer_preview:3135556';
  const youtube = 'bz:youtube_music:dQw4w9WgXcQ';

  test('Spotify catalog track cannot masquerade as playable full audio', () {
    expect(isSpotifyTrackId(spotify), isTrue);
    expect(isMetadataOnlyTrackId(spotify), isTrue);
    expect(canQueueTrackId(spotify), isFalse);
    expect(canOfferPlaybackAction(spotify), isFalse);
    expect(canRequestOfflineDownload(spotify), isFalse);
  });

  test('Deezer full song cannot be queued without a partner stream', () {
    expect(isDeezerTrackId(deezer), isTrue);
    expect(isMetadataOnlyTrackId(deezer), isTrue);
    expect(canQueueTrackId(deezer), isFalse);
    expect(canOfferPlaybackAction(deezer, hasPreview: true), isFalse);
    expect(canRequestOfflineDownload(deezer), isFalse);
  });

  test('Deezer short-form preview is explicitly separate from full song', () {
    expect(isDeezerPreview(preview), isTrue);
    expect(canQueueTrackId(preview), isTrue);
    expect(canOfferPlaybackAction(preview), isTrue);
    expect(canRequestOfflineDownload(preview), isFalse);
  });

  test('YouTube Music songs are visible videos, never native audio', () {
    expect(isYouTubeSongId(youtube), isTrue);
    expect(canQueueTrackId(youtube), isFalse);
    expect(canOfferPlaybackAction(youtube), isTrue);
    expect(canRequestOfflineDownload(youtube), isFalse);
  });

  test('Breezze licensed original recordings still permit native playback', () {
    expect(canQueueTrackId('approved-catalog-uuid'), isTrue);
    expect(canOfferPlaybackAction('approved-catalog-uuid'), isTrue);
  });
}
