import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/deezer_playback_handoff.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  const deezerId = '3135556';

  test('Deezer offers official full-track handoff and explicit short preview', () {
    expect(isDeezerTrackId('bz:deezer:$deezerId'), isTrue);
    expect(isDeezerPreview('bz:deezer_preview:$deezerId'), isTrue);
    expect(canOfferPlaybackAction('bz:deezer:$deezerId'), isTrue);
    expect(canQueueTrackId('bz:deezer:$deezerId'), isFalse);
    expect(isMetadataOnlyTrackId('bz:deezer:$deezerId'), isTrue);
    expect(canQueueTrackId('bz:deezer_preview:$deezerId'), isTrue);
    expect(canRequestOfflineDownload('bz:deezer:$deezerId'), isFalse);
    expect(canRequestOfflineDownload('bz:deezer_preview:$deezerId'), isFalse);
  });

  test('Deezer provider IDs accept only numeric track identifiers', () {
    expect(DeezerPlaybackHandoff.deezerIdFromBreezze(
      'bz:deezer:$deezerId',
    ), deezerId);
    expect(DeezerPlaybackHandoff.deezerIdFromBreezze(
      'bz:deezer_preview:$deezerId',
    ), deezerId);
    expect(DeezerPlaybackHandoff.deezerIdFromBreezze(
      'bz:deezer:../settings',
    ), isNull);
    expect(DeezerPlaybackHandoff.deezerIdFromBreezze(
      'bz:spotify:4iV5W9uYEdYUVa79Axb7Rh',
    ), isNull);
    expect(() => DeezerPlaybackHandoff.trackUrl('../settings'),
      throwsArgumentError);
  });

  test('Deezer official playback links never embed raw media tokens', () {
    final uri = DeezerPlaybackHandoff.trackUrl(deezerId);
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.deezer.com');
    expect(uri.path, '/track/$deezerId');
    expect(uri.query, isEmpty);
  });

  test('Deezer search is same-origin and encodes user input safely', () {
    final uri = DeezerPlaybackHandoff.searchUrl('Afrobeats & Amapiano');
    expect(uri.host, 'www.deezer.com');
    expect(uri.pathSegments.first, 'search');
    expect(uri.pathSegments.last, 'Afrobeats & Amapiano');
    expect(uri.query, isEmpty);
    expect(() => DeezerPlaybackHandoff.searchUrl(' '), throwsArgumentError);
  });

  test('YouTube video IDs never appear as Deezer music', () {
    expect(DeezerPlaybackHandoff.deezerIdFromBreezze(
      'bz:youtube_music:dQw4w9WgXcQ',
    ), isNull);
  });
}
