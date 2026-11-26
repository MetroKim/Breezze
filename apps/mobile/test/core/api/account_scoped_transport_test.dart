import 'dart:async';

import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Matcher sessionChanged() => isA<BreezzeApiException>()
    .having((error) => error.code, 'code', 'API_SESSION_CHANGED');

void main() {
  group('HTTP request account isolation', () {
    test('drops an old listener GET even when it returned HTTP 200', () async {
      final started = Completer<void>();
      final finish = Completer<http.Response>();
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        started.complete();
        return finish.future;
      });
      var owner = 'listener-a';
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: client,
      );
      api.accessToken = 'token-a';
      api.currentPrincipal = () => owner;

      final pending = api.me();
      await started.future;
      owner = 'listener-b';
      api.accessToken = 'token-b';
      finish.complete(http.Response('{"data":{"id":"listener-a"}}', 200));

      await expectLater(pending, throwsA(sessionChanged()));
      expect(sent, hasLength(1));
      expect(sent.single.headers['Authorization'], 'Bearer token-a');
      client.close();
    });

    test('drops stale response after same-user logout and login', () async {
      final started = Completer<void>();
      final reply = Completer<http.Response>();
      final client = MockClient((_) async {
        started.complete();
        return reply.future;
      });
      var authGeneration = 7;
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: client,
      );
      api.accessToken = 'first-login';
      api.currentPrincipal = () => '$authGeneration:listener-a';

      final pending = api.me();
      await started.future;
      authGeneration++; // Sign out and subsequently sign in as listener A.
      api.accessToken = 'second-login';
      reply.complete(http.Response('{"data":{"id":"listener-a"}}', 200));

      await expectLater(pending, throwsA(sessionChanged()));
      client.close();
    });

    test('never retries a 401 under a different listener', () async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response('{}', 401);
      });
      var owner = 'listener-a';
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: client,
      );
      api.accessToken = 'token-a';
      api.currentPrincipal = () => owner;
      api.onUnauthorized = () async {
        owner = 'listener-b';
        api.accessToken = 'token-b';
        return true;
      };

      await expectLater(api.me(), throwsA(sessionChanged()));
      expect(sent, hasLength(1));
      expect(sent.single.headers['Authorization'], 'Bearer token-a');
      client.close();
    });

    test('allows a genuine same-listener token refresh', () async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return sent.length == 1
            ? http.Response('{}', 401)
            : http.Response('{"data":{"id":"listener-a"}}', 200);
      });
      const owner = 'listener-a';
      final api = BreezzeApi(
        baseUrl: 'https://api.breezze.test',
        client: client,
      );
      api.accessToken = 'expired-token-a';
      api.currentPrincipal = () => owner;
      api.onUnauthorized = () async {
        api.accessToken = 'refreshed-token-a';
        return true;
      };

      final response = await api.me();
      expect(response['id'], 'listener-a');
      expect(sent, hasLength(2));
      expect(sent[0].headers['Authorization'], 'Bearer expired-token-a');
      expect(sent[1].headers['Authorization'], 'Bearer refreshed-token-a');
      client.close();
    });

    final mutations = <String, Future<dynamic> Function(BreezzeApi)>{
      'POST': (api) => api.youtubeAccountStart(),
      'PATCH': (api) => api.updateProfile(displayName: 'New name'),
      'DELETE': (api) => api.deleteAccount(password: 'redacted'),
    };
    for (final entry in mutations.entries) {
      test(entry.key + ' is never replayed after switching listener', () async {
        final sent = <http.Request>[];
        final client = MockClient((request) async {
          sent.add(request);
          return http.Response('{}', 401);
        });
        var owner = 'listener-a';
        final api = BreezzeApi(
          baseUrl: 'https://api.breezze.test',
          client: client,
        );
        api.accessToken = 'token-a';
        api.currentPrincipal = () => owner;
        api.onUnauthorized = () async {
          owner = 'listener-b';
          api.accessToken = 'token-b';
          return true;
        };

        await expectLater(entry.value(api), throwsA(sessionChanged()));
        expect(sent, hasLength(1));
        expect(sent.single.method, entry.key);
        expect(sent.single.headers['Authorization'], 'Bearer token-a');
        client.close();
      });
    }
  });
}
