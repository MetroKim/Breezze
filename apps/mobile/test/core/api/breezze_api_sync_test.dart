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
  group('BreezzeApi offline synchronization', () {
    test('records recent history using the non-qualified recent endpoint', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response('{"data":{"recorded":true}}', 200);
        }),
      )..accessToken = 'token';

      final result = await api.recordRecent('track-id');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/home/recent');
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(captured.body), {'trackId': 'track-id'});
      expect(result['recorded'], isTrue);
    });

    test('downloads a private cloud favorites snapshot without mixing accounts', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(jsonEncode({
            'data': [
              {
                'trackId': 'canonical-uuid',
                'track': {
                  'id': 'canonical-uuid',
                  'title': 'Cloud Song',
                  'duration': 180,
                  'artist': {'name': 'Cloud Artist'},
                },
              },
            ],
          }), 200);
        }),
      )..accessToken = 'owner-a-token';

      final rows = await api.fetchCloudFavorites();
      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/library/favorites');
      expect(captured.headers['Authorization'], 'Bearer owner-a-token');
      expect(rows.single['trackId'], 'canonical-uuid');
    });

    test('adds favorites through the authenticated library endpoint', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response('{"data":{"trackId":"track-id"}}', 200);
        }),
      )..accessToken = 'token';

      await api.addFavorite('track-id');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/library/favorites');
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(captured.body), {'trackId': 'track-id'});
    });

    test('removes favorites through the authenticated library endpoint', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response('{"data":{"removed":true}}', 200);
        }),
      )..accessToken = 'token';

      await api.removeFavorite('track/id');

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/api/v1/library/favorites/track%2Fid');
      expect(captured.headers['Authorization'], 'Bearer token');
    });
  });
}
