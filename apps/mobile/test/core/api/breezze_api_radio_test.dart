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
  group('BreezzeApi radio directory', () {
    test('loads typed station metadata through the authenticated API client', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":[{"id":"station-1","name":"Breezze Live","isLive":true}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..accessToken = 'access-token';

      final stations = await api.getRadioStations();

      expect(captured.url.path, '/api/v1/radio/stations');
      expect(captured.headers['Authorization'], 'Bearer access-token');
      expect(stations, [
        {'id': 'station-1', 'name': 'Breezze Live', 'isLive': true},
      ]);
    });

    test('loads station schedule through the same API client', () async {
      late http.Request captured;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((request) async {
          captured = request;
          return http.Response(
            '{"data":{"id":"station/one","programs":[{"title":"Morning Mix","durationMin":60}]}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final station = await api.getRadioStation('station/one');

      expect(captured.url.path, '/api/v1/radio/stations/station%2Fone');
      expect(station['id'], 'station/one');
      expect(station['programs'], [
        {'title': 'Morning Mix', 'durationMin': 60},
      ]);
    });

    test('rejects malformed station directory envelopes', () async {
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: _RecordingClient((_) async => http.Response('{"data":{}}', 200)),
      );

      expect(api.getRadioStations(), throwsFormatException);
    });
  });
}
