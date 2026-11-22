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
  group('BreezzeApi in-app support', () {
    test('submits a support request through the authenticated API', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":{"id":"request-1","status":"open"}}',
            201,
          );
        }),
      )..accessToken = 'token';

      final result = await api.createSupportRequest(
        category: 'playback',
        subject: 'Playback stops',
        message: 'The player stops after a few seconds.',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/support/requests');
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(jsonDecode(captured.body), {
        'category': 'playback',
        'subject': 'Playback stops',
        'message': 'The player stops after a few seconds.',
      });
      expect(result['id'], 'request-1');
    });

    test("loads only the signed-in user's support request collection", () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":[{"id":"request-1","subject":"Playback stops","status":"open"}]}',
            200,
          );
        }),
      )..accessToken = 'token';

      final requests = await api.supportRequests();

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/support/requests');
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(requests.single['id'], 'request-1');
    });
  });
}
