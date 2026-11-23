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

  test('legacy link submits both credentials only to the dedicated route', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.path, '/api/v1/auth/supabase/link-legacy');
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'accessToken', 'legacyEmail', 'legacyPassword',
      });
      expect(body['accessToken'], 'verified-supabase-token');
      expect(body['legacyEmail'], 'old@example.com');
      expect(body['legacyPassword'], 'old-password');
      return http.Response(jsonEncode({
        'data': {
          'accessToken': 'legacy-mapped-access',
          'refreshToken': 'legacy-mapped-refresh',
          'user': {'id': 'original-user-id', 'email': 'old@example.com'},
        },
      }), 200);
    });
    final api = BreezzeApi(baseUrl: 'https://api.breezze.test', client: client);
    final result = await api.linkLegacySupabaseAccount(
      supabaseAccessToken: 'verified-supabase-token',
      legacyEmail: 'old@example.com',
      legacyPassword: 'old-password',
    );
    expect(result.userId, 'original-user-id');
    expect(requests, 1);
  });

  test('link failure is not retried through regular session refresh', () async {
    var calls = 0;
    var refreshes = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        '{"message":"LEGACY_CREDENTIALS_INVALID","error":"Unauthorized","statusCode":401}',
        401,
      );
    });
    final api = BreezzeApi(baseUrl: 'https://api.breezze.test', client: client);
    api.onUnauthorized = () async {
      refreshes++;
      return true;
    };
    await expectLater(
      api.linkLegacySupabaseAccount(
        supabaseAccessToken: 'verified-supabase-token',
        legacyEmail: 'old@example.com',
        legacyPassword: 'wrong-password',
      ),
      throwsA(isA<BreezzeApiException>().having(
        (e) => e.code, 'code', 'LEGACY_CREDENTIALS_INVALID',
      )),
    );
    expect(calls, 1);
    expect(refreshes, 0);
  });

  test('original-account conflict preserves Nest machine-readable code', () async {
    final client = MockClient((request) async => http.Response(
      '{"message":"LEGACY_ACCOUNT_LINK_REQUIRED","error":"Conflict","statusCode":409}',
      409,
    ));
    final api = BreezzeApi(baseUrl: 'https://api.breezze.test', client: client);
    await expectLater(
      api.exchangeSupabaseAccessToken('verified-supabase-token'),
      throwsA(isA<BreezzeApiException>().having(
        (e) => e.code, 'code', 'LEGACY_ACCOUNT_LINK_REQUIRED',
      )),
    );
  });
}
