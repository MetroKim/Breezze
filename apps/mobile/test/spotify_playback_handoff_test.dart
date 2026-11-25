import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/spotify_playback_handoff.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  const spotifyId = '4iV5W9uYEdYUVa79Axb7Rh';

  test('Spotify tracks are an official-app action, never native audio or offline', () {
    expect(isSpotifyTrackId('bz:spotify:$spotifyId'), isTrue);
    expect(canOfferPlaybackAction('bz:spotify:$spotifyId'), isTrue);
    expect(isMetadataOnlyTrackId('bz:spotify:$spotifyId'), isTrue);
    expect(canQueueTrackId('bz:spotify:$spotifyId'), isFalse);
    expect(canRequestOfflineDownload('bz:spotify:$spotifyId'), isFalse);
  });

  test('YouTube stays video-only, never a native audio source', () {
    const id = 'bz:youtube_music:abcdefghijk';
    expect(isYouTubeSongId(id), isTrue);
    expect(canOfferPlaybackAction(id), isTrue);
    expect(canQueueTrackId(id), isFalse);
    expect(canRequestOfflineDownload(id), isFalse);
  });

  test('Spotify track links cannot escape Spotify origin', () {
    expect(SpotifyPlaybackHandoff.spotifyIdFromBreezze(
      'bz:spotify:$spotifyId',
    ), spotifyId);
    expect(SpotifyPlaybackHandoff.trackUrl(spotifyId).toString(),
      'https://open.spotify.com/track/$spotifyId');
    expect(SpotifyPlaybackHandoff.spotifyIdFromBreezze(
      'bz:spotify:../admin',
    ), isNull);
    expect(() => SpotifyPlaybackHandoff.trackUrl('../admin'), throwsArgumentError);
  });

  test('Spotify app search deep links encode user inputs safely', () {
    final uri = SpotifyPlaybackHandoff.searchUrl('Afrobeat & Amapiano');
    expect(uri.host, 'open.spotify.com');
    expect(uri.pathSegments.first, 'search');
    expect(uri.pathSegments.last, 'Afrobeat & Amapiano');
    expect(uri.query, isEmpty);
    expect(() => SpotifyPlaybackHandoff.searchUrl('   '), throwsArgumentError);
  });
}
