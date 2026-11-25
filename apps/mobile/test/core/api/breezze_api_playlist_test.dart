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
  group('BreezzeApi playlist synchronization', () {
    test('posts a client UUID when replaying a local playlist creation', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response('{"data":{"id":"client-id","name":"Offline"}}', 200);
        }),
      )..accessToken = 'owner-a';

      await api.createPlaylist('Offline', id: 'client-id');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/playlists');
      expect(captured.headers['Authorization'], 'Bearer owner-a');
      expect(jsonDecode(captured.body), {
        'id': 'client-id',
        'name': 'Offline',
      });
    });

    test('loads a playlist with server-ordered track metadata', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":{"id":"playlist-1","name":"Road Trip","items":[{"trackId":"track-1","position":0,"track":{"id":"track-1","title":"First","duration":180,"artist":{"name":"Artist"}}}]}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..accessToken = 'token';

      final playlist = await api.getPlaylist('playlist-1');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/playlists/playlist-1');
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(playlist['name'], 'Road Trip');
      expect((playlist['items'] as List).single['track']['title'], 'First');
    });

    test('persists an exact ordered track list through the authenticated API', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response('{"data":{"reordered":true,"count":3}}', 200);
        }),
      )..accessToken = 'token';

      final result = await api.reorderPlaylistTracks(
        'playlist/one',
        ['track-3', 'track-1', 'track-2'],
      );

      expect(captured.method, 'PATCH');
      expect(captured.url.path, '/api/v1/playlists/playlist%2Fone/tracks/order');
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(captured.body), {
        'trackIds': ['track-3', 'track-1', 'track-2'],
      });
      expect(result['reordered'], isTrue);
    });
  });
}
