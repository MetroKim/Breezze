import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogApi extends BreezzeApi {
  _CatalogApi(this.response) : super(baseUrl: 'https://breezze.test');

  final Map<String, dynamic> response;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> searchMusicCatalogs(String query) async {
    calls++;
    return response;
  }
}

class _CatalogSession extends AuthSessionController {
  _CatalogSession(this.testApi);
  final BreezzeApi testApi;

  @override
  AuthState build() => const AuthSignedOut();

  @override
  BreezzeApi get api => testApi;
}

final spotify = {
  'providerTrackId': '4iV5W9uYEdYUVa79Axb7Rh',
  'title': 'Song', 'artist': 'Artist', 'durationSec': 200,
};
final deezer = {
  'providerTrackId': '3135556',
  'title': 'Song', 'artist': 'Artist', 'durationSec': 201,
};

Future<List<ProviderTrack>> searchWith(
    Map<String, dynamic> response, String expectedSource) async {
  final api = _CatalogApi(response);
  final container = ProviderContainer(overrides: [
    authSessionProvider.overrideWith(() => _CatalogSession(api)),
  ]);
  try {
    final operation = await container.read(catalogSourceProvider).search('Song');
    expect(api.calls, 1);
    expect(operation, isA<ProviderOk<List<ProviderTrack>>>());
    final tracks = (operation as ProviderOk<List<ProviderTrack>>).value;
    expect(tracks.first.breezzeTrackId, startsWith('bz:$expectedSource:'));
    return tracks;
  } finally {
    container.dispose();
  }
}

void main() {
  test('single unified backend result wins over separate provider shelves', () async {
    final tracks = await searchWith({
      'tracks': [
        {...spotify, 'providerId': 'spotify', 'alternateCatalogIds': [
          {'providerId': 'deezer', 'providerTrackId': '3135556'},
        ]},
      ],
      'providers': [
        {'providerId': 'spotify', 'result': {'kind': 'ok', 'value': [spotify]}},
        {'providerId': 'deezer', 'result': {'kind': 'ok', 'value': [deezer]}},
      ],
    }, 'spotify');
    expect(tracks, hasLength(1));
    expect(tracks.single.providerTrackId, 'spotify:4iV5W9uYEdYUVa79Axb7Rh');
  });

  test('legacy API fallback deduplicates matching recordings conservatively', () async {
    final tracks = await searchWith({
      'providers': [
        {'providerId': 'spotify', 'result': {'kind': 'ok', 'value': [spotify]}},
        {'providerId': 'deezer', 'result': {'kind': 'ok', 'value': [deezer]}},
      ],
    }, 'spotify');
    expect(tracks, hasLength(1));
  });

  test('different editions are retained instead of being incorrectly merged', () async {
    final tracks = await searchWith({
      'providers': [
        {'providerId': 'spotify', 'result': {'kind': 'ok', 'value': [spotify]}},
        {'providerId': 'deezer', 'result': {'kind': 'ok', 'value': [
          {...deezer, 'title': 'Song (Live)', 'durationSec': 240},
        ]}},
      ],
    }, 'spotify');
    expect(tracks.map((t) => t.breezzeTrackId),
        ['bz:spotify:4iV5W9uYEdYUVa79Axb7Rh', 'bz:deezer:3135556']);
  });

  test('Deezer alone remains searchable if Spotify is unavailable', () async {
    final tracks = await searchWith({
      'tracks': [{...deezer, 'providerId': 'deezer'}],
      'providers': [
        {'providerId': 'spotify', 'result': {'kind': 'error'}},
        {'providerId': 'deezer', 'result': {'kind': 'ok', 'value': [deezer]}},
      ],
    }, 'deezer');
    expect(tracks, hasLength(1));
  });
}
