import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:breezze/core/api/breezze_api.dart';

void main() {
  test('social providers are discovered from the backend, not hardcoded', () async {
    late http.Request captured;
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'data': {'google': true, 'apple': false}}), 200,
        );
      }),
    );
    final providers = await api.socialProviders();
    expect(providers, {'google': true, 'apple': false});
    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/auth/social/providers');
  });

  test('starting Google OAuth returns app-only one-time pairing details', () async {
    late http.Request captured;
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': {
          'id': 'flow-id',
          'secret': 'app-only-random-secret',
          'authorizationUrl': 'https://accounts.google.com/o/oauth2/v2/auth',
        }}), 200);
      }),
    );
    final started = await api.startSocialLogin('google');
    expect(started['id'], 'flow-id');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/auth/social/google/start');
    expect(captured.url.query, isEmpty);
    expect(captured.body, '{}');
  });

  test('invalid provider does not result in an HTTP request', () async {
    var calls = 0;
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect(() => api.startSocialLogin('untrusted'), throwsArgumentError);
    expect(calls, 0);
  });

  test('polling sends secret inside POST body, never URL', () async {
    late http.Request captured;
    final api = BreezzeApi(
      baseUrl: 'https://breezze.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': {
          'status': 'completed',
          'session': {
            'accessToken': 'access',
            'refreshToken': 'refresh',
            'user': {'id': 'user-1', 'email': 'user@example.com'},
          },
        }}), 200);
      }),
    );
    final result = await api.pollSocialLogin(flowId: 'flow-id',
      secret: 'browser-must-not-know-this-secret');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/auth/social/poll');
    expect(captured.url.query, isEmpty);
    expect(jsonDecode(captured.body), {
      'id': 'flow-id',
      'secret': 'browser-must-not-know-this-secret',
    });
    expect(AuthResponse.fromJson(
      Map<String, dynamic>.from(result['session'] as Map)).userId, 'user-1');
  });
}
