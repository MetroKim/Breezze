import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  BreezzeApi apiFor(http.Response Function() response) => BreezzeApi(
        baseUrl: 'https://api.breezze.example',
        client: MockClient((_) async => response()),
      );

  test('HTML 502 is a sanitized typed HTTP error, not leaked HTML', () async {
    final api = apiFor(() => http.Response(
          '<html><title>Private upstream debug data</title></html>',
          502,
        ));
    await expectLater(
      api.searchMusic('example'),
      throwsA(isA<BreezzeApiException>()
          .having((e) => e.code, 'code', 'HTTP_502')
          .having((e) => e.message, 'safe message',
              isNot(contains('Private upstream')))),
    );
  });

  test('malformed success JSON cannot crash screens as a FormatException',
      () async {
    final api = apiFor(() => http.Response('broken-json:', 200));
    await expectLater(
      api.searchMusic('example'),
      throwsA(isA<BreezzeApiException>()
          .having((e) => e.code, 'code', 'API_RESPONSE_INVALID')),
    );
  });

  test('array instead of an API object is rejected as an invalid envelope',
      () async {
    final api = apiFor(() => http.Response('[]', 200));
    await expectLater(
      api.searchMusic('example'),
      throwsA(isA<BreezzeApiException>()
          .having((e) => e.code, 'code', 'API_RESPONSE_INVALID')),
    );
  });

  test('valid backend error envelopes retain their machine-readable code',
      () async {
    final api = apiFor(() => http.Response(
          '{"error":{"code":"RIGHTS_NOT_GRANTED","message":"Not permitted"}}',
          403,
          headers: {'content-type': 'application/json'},
        ));
    await expectLater(
      api.searchMusic('example'),
      throwsA(isA<BreezzeApiException>()
          .having((e) => e.code, 'code', 'RIGHTS_NOT_GRANTED')),
    );
  });
}
