import 'dart:convert';

import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('BreezzeApi personalized home feed', () {
    test('loads home sections through the authenticated API', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":[{"sectionType":"personalized","title":"Made for You","layout":"rail","trackIds":["track-1"]}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..accessToken = 'session-token';

      final sections = await api.homeFeed();

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/home');
      expect(captured.headers['Authorization'], 'Bearer session-token');
      expect(sections.single['sectionType'], 'personalized');
      expect(sections.single['trackIds'], ['track-1']);
    });

    test('loads canonical catalog metadata for a recommendation', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":{"id":"track-1","title":"Song","duration":184,"artist":{"name":"Artist"}}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..accessToken = 'session-token';

      final song = await api.catalogSong('track-1');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/catalog/songs/track-1');
      expect(captured.headers['Authorization'], 'Bearer session-token');
      expect(song['id'], 'track-1');
      expect((song['artist'] as Map)['name'], 'Artist');
    });

    test('encodes canonical track IDs as one path segment', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response('{"data":{"id":"track/one","title":"Song"}}', 200);
        }),
      );

      await api.catalogSong('track/one');

      expect(captured.url.path, '/api/v1/catalog/songs/track%2Fone');
    });
  });
}
