import 'dart:convert';

import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Supabase exchange is never retried via Breezze 401 refresh', () async {
    var calls = 0;
    var refreshes = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/v1/auth/supabase/exchange');
      expect(jsonDecode(request.body)['accessToken'], 'supabase-access-token');
      return http.Response(
        jsonEncode({
          'error': {'code': 'SUPABASE_TOKEN_REJECTED', 'message': 'Invalid token'},
        }),
        401,
      );
    });
    final api = BreezzeApi(baseUrl: 'https://api.breezze.test', client: client);
    api.onUnauthorized = () async {
      refreshes++;
      return true;
    };

    await expectLater(
      api.exchangeSupabaseAccessToken('supabase-access-token'),
      throwsA(isA<BreezzeApiException>()),
    );
    expect(calls, 1);
    expect(refreshes, 0);
  });

  test('Supabase exchange returns a mapped Breezze session', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'data': {
              'accessToken': 'mapped-access',
              'refreshToken': 'mapped-refresh',
              'user': {'id': 'mapped-user-id', 'email': 'listener@example.com'},
            },
          }),
          200,
        ));
    final api = BreezzeApi(baseUrl: 'https://api.breezze.test', client: client);
    final session = await api.exchangeSupabaseAccessToken('valid-supabase-token');
    expect(session.accessToken, 'mapped-access');
    expect(session.refreshToken, 'mapped-refresh');
    expect(session.userId, 'mapped-user-id');
    expect(session.email, 'listener@example.com');
  });

  test('existing private API requests still retry after authorized refresh', () async {
    var calls = 0;
    var refreshes = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response('{"error":{"code":"HTTP_401"}}', 401);
      }
      return http.Response('{"data":{"results":[]}}', 200);
    });
    final api = BreezzeApi(baseUrl: 'https://api.breezze.test', client: client);
    api.onUnauthorized = () async {
      refreshes++;
      return true;
    };

    final result = await api.searchMusic('track');
    expect(result['results'], isEmpty);
    expect(calls, 2);
    expect(refreshes, 1);
  });
}
