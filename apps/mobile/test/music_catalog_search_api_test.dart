import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/core/api/breezze_api.dart';

void main() {
  test('Breezze uses one authenticated backend call to search Spotify and Deezer', () async {
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'Bearer test-listener-token');
      return http.Response(jsonEncode({'data': {
        'query': 'Afrobeat & Bongo',
        'partial': false,
        'providers': [
          {
            'providerId': 'spotify', 'displayName': 'Spotify',
            'result': {'kind': 'ok', 'value': [
              {'providerTrackId': '4iV5W9uYEdYUVa79Axb7Rh',
               'title': 'Song', 'artist': 'Artist'},
            ]},
          },
          {
            'providerId': 'deezer', 'displayName': 'Deezer',
            'result': {'kind': 'ok', 'value': [
              {'providerTrackId': '3135556',
               'title': 'Song', 'artist': 'Artist'},
            ]},
          },
        ],
      }}), 200, headers: {'content-type': 'application/json'});
    });
    final api = BreezzeApi(baseUrl: 'https://breezze.test', client: client)
      ..accessToken = 'test-listener-token';
    final data = await api.searchMusicCatalogs('Afrobeat & Bongo');
    expect(requested!.path, '/api/v1/providers/music/search');
    expect(requested!.queryParameters['q'], 'Afrobeat & Bongo');
    expect(data['partial'], false);
    final shelves = data['providers'] as List;
    expect(shelves.map((row) => (row as Map)['providerId']).toList(),
        ['spotify', 'deezer']);
    expect(shelves.length, 2);
    client.close();
  });

  test('partial Spotify outage retains Deezer discovery results', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'data': {
      'query': 'piano', 'partial': true,
      'providers': [
        {'providerId': 'spotify', 'result': {
          'kind': 'error', 'code': 'MUSIC_PROVIDER_TIMEOUT',
          'message': 'Music catalog provider timed out', 'retryable': true,
        }},
        {'providerId': 'deezer', 'result': {
          'kind': 'ok', 'value': [
            {'providerTrackId': '3135556', 'title': 'Piano', 'artist': 'A'},
          ],
        }},
      ],
    }}), 200));
    final api = BreezzeApi(baseUrl: 'https://breezze.test', client: client);
    final result = await api.searchMusicCatalogs('piano');
    expect(result['partial'], true);
    final shelves = result['providers'] as List;
    expect((shelves[1] as Map)['result'], containsPair('kind', 'ok'));
    client.close();
  });
}
