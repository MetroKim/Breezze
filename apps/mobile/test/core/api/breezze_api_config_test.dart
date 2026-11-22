import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Breezze API origin configuration', () {
    test('fails with an actionable error when no origin is configured', () async {
      final api = BreezzeApi(baseUrl: '');
      await expectLater(
        api.me(),
        throwsA(isA<BreezzeApiException>().having((error) => error.code, 'code', 'API_URL_NOT_CONFIGURED')),
      );
    });

    test('rejects a URL containing a path instead of an origin', () async {
      final api = BreezzeApi(baseUrl: 'https://api.breezze.test/api');
      await expectLater(
        api.me(),
        throwsA(isA<BreezzeApiException>().having((error) => error.code, 'code', 'API_URL_INVALID')),
      );
    });
  });
}
