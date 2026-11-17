import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BitChordAdapter search parsing', () {
    test('parses tracks from a backend search response', () async {
      final adapter = BitChordAdapter(
        http: _FakeBackend(),
        apiKey: 'test-key',
      );

      final result = await adapter.search('kavinsky nightcall');

      expect(result, isA<ProviderOk<List<ProviderTrack>>>());
      final tracks = (result as ProviderOk<List<ProviderTrack>>).value;
      expect(tracks, isNotEmpty);
      expect(tracks.first.title, 'Nightcall');
      expect(tracks.first.artist, 'Kavinsky');
      expect(tracks.first.providerTrackId, 'abc123');
    });

    test('search errors map to ProviderError, never a fake result', () async {
      final adapter = BitChordAdapter(
        http: _FailingBackend(),
        apiKey: 'test-key',
      );

      final result = await adapter.search('anything');

      expect(result, isA<ProviderError>());
    });

    test('playback unsupported without signer', () async {
      final adapter = BitChordAdapter(
        http: _FakeBackend(),
        apiKey: 'test-key',
        signer: null,
      );

      expect(adapter.supportsPlayback, isFalse);

      final result = await adapter.resolvePlayback(
        'abc123',
        ProviderUserContext(
            userId: 'u', territory: 'IN', subscriptionTier: 'premium'),
      );

      expect(result, isA<ProviderUnsupported>());
    });
  });
}

class _FakeBackend implements BackendHttp {
  @override
  Future<Object?> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    return {
      'contents': [
        {
          'musicShelfRenderer': {
            'contents': [
              {
                'musicResponsiveListItemRenderer': {
                  'playlistItemData': {'videoId': 'abc123'},
                  'musicResponsiveListItemFlexColumnRenderer': [
                    {
                      'text': {
                        'runs': [
                          {'text': 'Nightcall'}
                        ]
                      }
                    },
                    {
                      'text': {
                        'runs': [
                          {'text': 'Kavinsky'}
                        ]
                      }
                    },
                  ],
                  'musicResponsiveListItemFixedColumnRenderer': [
                    {
                      'text': {
                        'runs': [
                          {'text': '4:14'}
                        ]
                      }
                    }
                  ],
                }
              }
            ]
          }
        }
      ]
    };
  }
}

class _FailingBackend implements BackendHttp {
  @override
  Future<Object?> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    throw Exception('network down');
  }
}
