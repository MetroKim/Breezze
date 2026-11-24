import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:breezze/core/api/breezze_api.dart';

void main() {
  test('saved albums list uses account JWT and correct cursor', () async {
    final calls = <http.Request>[];
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode({'data': {
            'items': [],
            'nextCursor': null,
          }}),
          200,
        );
      }),
    )..accessToken = 'owner-a-access-token';

    final result = await api.getSavedAlbums(cursor: 'cursor-id');
    expect(result['items'], isEmpty);
    expect(calls.single.url.path, '/api/v1/library/albums');
    expect(calls.single.url.queryParameters['cursor'], 'cursor-id');
    expect(calls.single.headers['Authorization'], 'Bearer owner-a-access-token');
  });

  test('saved album upsert posts metadata without any playback grant', () async {
    late http.Request captured;
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': {'externalAlbumId': '123'}}), 201);
      }),
    )..accessToken = 'token';

    await api.upsertSavedAlbum(
      externalAlbumId: '123',
      title: 'Album',
      artist: 'Artist',
      genres: ['Jazz'],
      isCompilation: true,
      isPinned: true,
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/library/albums');
    expect(body, containsPair('externalAlbumId', '123'));
    expect(body, containsPair('isCompilation', true));
    expect(body, containsPair('isPinned', true));
    expect(body.containsKey('streamUrl'), isFalse);
    expect(body.containsKey('playback'), isFalse);
  });

  test('removing a saved album uses an authenticated owner-bound request', () async {
    late http.Request captured;
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': {'removed': true}}), 200);
      }),
    )..accessToken = 'owner-a-access-token';

    await api.deleteSavedAlbum('321');
    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/api/v1/library/albums/321');
    expect(captured.headers['Authorization'], 'Bearer owner-a-access-token');
  });
}
