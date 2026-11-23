import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/core/api/breezze_api.dart';

void main() {
  test('searchAllProviders calls the federated catalog endpoint', () async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'data': {
            'query': 'afrobeats',
            'providers': [
              {
                'providerId': 'audius',
                'displayName': 'Audius',
                'result': {
                  'kind': 'ok',
                  'value': [
                    {
                      'providerTrackId': 'track-123',
                      'title': 'Example',
                      'artist': 'Example Artist',
                      'durationSec': 180,
                    }
                  ],
                },
              },
              {
                'providerId': 'youtube_music',
                'displayName': 'YouTube Music',
                'result': {
                  'kind': 'error',
                  'code': 'YTMUSIC_UNAVAILABLE',
                  'retryable': true,
                  'message': 'temporarily unavailable',
                },
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = BreezzeApi(baseUrl: 'https://api.example.test', client: client);

    final result = await api.searchAllProviders('afrobeats');

    expect(requestedUri!.path, '/api/v1/providers/search');
    expect(requestedUri!.queryParameters['q'], 'afrobeats');
    expect(result['query'], 'afrobeats');
    final providers = result['providers'] as List;
    expect(providers, hasLength(2));
    expect((providers[0] as Map)['providerId'], 'audius');
    expect((providers[1] as Map)['result'], containsPair('kind', 'error'));
  });

  test('searchAllProviders safely encodes query strings', () async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(jsonEncode({'data': {'query': 'A B & C', 'providers': []}}), 200);
    });
    final api = BreezzeApi(baseUrl: 'https://api.example.test', client: client);

    await api.searchAllProviders('A B & C');

    expect(requestedUri!.queryParameters['q'], 'A B & C');
  });
}
