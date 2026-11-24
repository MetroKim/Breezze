import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('licensed video API uses authenticated Breezze routes only', () async {
    final requests = <http.Request>[];
    const id = '123e4567-e89b-42d3-a456-426614174000';
    final api = BreezzeApi(
      baseUrl: 'https://api.breezze.test',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"allowed":true,"items":[]}', 200,
            headers: {'content-type': 'application/json'});
      }),
    )..accessToken = 'video-test-token';

    await api.licensedVideos();
    await api.videoPlayback(id);
    await api.authorizeVideoDownload(id);
    await api.revalidateVideoDownload(id);
    await api.videoDownloads();
    await api.removeVideoDownload(id);

    expect(requests.map((r) => r.method).toList(),
        ['GET', 'GET', 'POST', 'POST', 'GET', 'DELETE']);
    expect(requests.map((r) => r.url.path).toList(), [
      '/api/v1/videos/catalog',
      '/api/v1/videos/$id/playback',
      '/api/v1/videos/$id/download',
      '/api/v1/videos/$id/download/revalidate',
      '/api/v1/videos/downloads',
      '/api/v1/videos/$id/download',
    ]);
    expect(requests.every((r) =>
        r.headers['Authorization'] == 'Bearer video-test-token'), isTrue);
    expect(requests.every((r) =>
        r.url.origin == 'https://api.breezze.test'), isTrue);
  });
}
