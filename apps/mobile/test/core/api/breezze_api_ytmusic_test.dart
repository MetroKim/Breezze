import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Unofficial YouTube Music catalog API', () {
    test('routes all supported catalog requests through the Breezze API', () async {
      final requests = <http.Request>[];
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"kind":"ok","value":{}}', 200,
              headers: {'content-type': 'application/json'});
        }),
      )..accessToken = 'session-token';

      await api.ytMusicSearchArtists('Bongo Flava & Afro');
      await api.ytMusicArtist('UCabcdefghij');
      await api.ytMusicCharts(country: 'TZ');
      await api.ytMusicWatchQueue('abcdefghijk', limit: 12);
      await api.ytMusicSuggestions('music & jazz', limit: 5);
      await api.ytMusicAlbum('MPREabcdefghij');
      await api.ytMusicPlaylist('OLAK5uy_abcdefghij', limit: 30);
      await api.ytMusicMoods();
      await api.ytMusicMoodPlaylists('example_params', limit: 15);
      await api.ytMusicExplore();

      expect(requests.length, 10);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(requests.every((r) =>
          r.headers['Authorization'] == 'Bearer session-token'), isTrue);
      expect(requests.every((r) =>
          r.url.origin == 'https://api.breezze.test'), isTrue);
      expect(requests.every((r) =>
          r.url.path.startsWith('/api/v1/providers/youtube_music/')), isTrue);

      expect(requests[0].url.path,
          '/api/v1/providers/youtube_music/artists/search');
      expect(requests[0].url.queryParameters['q'], 'Bongo Flava & Afro');
      expect(requests[1].url.path,
          '/api/v1/providers/youtube_music/artists/UCabcdefghij');
      expect(requests[2].url.queryParameters['country'], 'TZ');
      expect(requests[3].url.path,
          '/api/v1/providers/youtube_music/watch-queue/abcdefghijk');
      expect(requests[3].url.queryParameters['limit'], '12');
      expect(requests[4].url.queryParameters['q'], 'music & jazz');
      expect(requests[4].url.queryParameters['limit'], '5');
      expect(requests[5].url.path,
          '/api/v1/providers/youtube_music/albums/MPREabcdefghij');
      expect(requests[6].url.path,
          '/api/v1/providers/youtube_music/playlists/OLAK5uy_abcdefghij');
      expect(requests[6].url.queryParameters['limit'], '30');
      expect(requests[7].url.path,
          '/api/v1/providers/youtube_music/moods');
      expect(requests[8].url.queryParameters['params'], 'example_params');
      expect(requests[8].url.queryParameters['limit'], '15');
      expect(requests[9].url.path,
          '/api/v1/providers/youtube_music/explore');
    });

    test('does not mistake provider metadata for an audio playback grant', () async {
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: MockClient((_) async => http.Response(
          '{"kind":"ok","value":{"source":"youtube_music",'
          '"playbackAvailable":false,"tracks":[]}}', 200,
          headers: {'content-type': 'application/json'},
        )),
      );
      final result = await api.ytMusicWatchQueue('abcdefghijk');
      expect(result['kind'], 'ok');
      expect((result['value'] as Map)['playbackAvailable'], false);
    });
  });
}
