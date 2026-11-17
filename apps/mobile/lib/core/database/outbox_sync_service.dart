import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/api/breezze_api.dart';
import '../../core/auth/auth_session.dart';
import 'database_providers.dart';

/// Drains the sync outbox against the backend. Called after sign-in
/// and after every local mutation while a session exists.
///
/// - favorite.add       → POST /library/favorites
/// - favorite.remove    → DELETE /library/favorites/:trackId
/// - recent.play        → POST /home/plays
///
/// An op is deleted only after the backend accepted it. On any
/// failure the drain stops and retries next time — offline actions
/// are never lost.
class OutboxSyncService {
  final Ref _ref;

  OutboxSyncService(this._ref);

  bool _draining = false;

  Future<void> drainIfSignedIn() async {
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return;
    if (_draining) return;
    _draining = true;
    try {
      final outbox = _ref.read(syncOutboxDaoProvider);
      final api = _ref.read(authSessionProvider.notifier).api;
      final territory = _ref.read(outboxTerritoryProvider);

      final ops = await outbox.pending();
      for (final op in ops) {
        final ok = await _apply(api, op.op, op.trackId, territory);
        if (!ok) return; // stop on first failure, keep the rest queued
        await outbox.remove(op.id);
      }
    } finally {
      _draining = false;
    }
  }

  Future<bool> _apply(
    BreezzeApi api,
    String op,
    String trackId,
    String territory,
  ) async {
    try {
      if (op == 'favorite.add') {
        return await _post(api, '/library/favorites', {
          'trackId': trackId,
        });
      } else if (op == 'favorite.remove') {
        final res = await api.delete('/library/favorites/$trackId');
        return res.statusCode < 400;
      } else if (op == 'recent.play') {
        return await _post(api, '/home/plays', {
          'trackId': trackId,
        });
      }
      // Unknown op type: drop it rather than loop forever.
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _post(BreezzeApi api, String path, Map<String, dynamic> body) async {
    final res = await api.post(path, body);
    return res.statusCode < 400;
  }
}

/// Territory for playback/plays endpoints; 'WW' default until the
/// onboarding flow sets the user's country.
final outboxTerritoryProvider = StateProvider<String>((ref) => 'WW');

final outboxSyncProvider = Provider<OutboxSyncService>(
  (ref) => OutboxSyncService(ref),
);

/// JSON helper kept off BreezzeApi — thin, no envelope assumptions
/// beyond status code, matching the backend's interceptor shape.
extension _BreezzeApiRaw on BreezzeApi {
  Future<http.Response> post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl/api/v1$path');
    return http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String path) async {
    final uri = Uri.parse('$baseUrl/api/v1$path');
    return http.delete(
      uri,
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
    );
  }
}
