import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('YouTube account routes require Breezze JWT and never send provider credentials', () async {
    final requests = <http.Request>[];
    final api = BreezzeApi(
      baseUrl: 'https://api.breezze.test',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"available":true,"connected":false}', 200,
            headers: {'content-type': 'application/json'});
      }),
    )..accessToken = 'breezze-session-token';

    await api.youtubeAccountStatus();
    await api.youtubeAccountStart();
    await api.youtubeAccountPlaylists();
    await api.youtubeAccountDisconnect();

    expect(requests.map((r) => r.url.path).toList(), [
      '/api/v1/youtube-account/status',
      '/api/v1/youtube-account/start',
      '/api/v1/youtube-account/playlists',
      '/api/v1/youtube-account/connection',
    ]);
    expect(requests.map((r) => r.method).toList(),
        ['GET', 'POST', 'GET', 'DELETE']);
    expect(requests.every((r) =>
        r.headers['Authorization'] == 'Bearer breezze-session-token'), isTrue);
    expect(requests.every((r) =>
        r.url.origin == 'https://api.breezze.test'), isTrue);
    expect(requests.every((r) =>
        !r.body.contains('refresh_token') &&
        !r.body.contains('client_secret')), isTrue);
  });
}
