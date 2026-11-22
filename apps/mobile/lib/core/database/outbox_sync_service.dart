import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/breezze_api.dart';
import '../../core/auth/auth_session.dart';
import 'database_providers.dart';

/// Drains the sync outbox through BreezzeApi after sign-in.
///
/// External provider IDs are converged to canonical catalog IDs before they
/// are written to user-owned backend records. Network/API failures leave the
/// current operation and every later operation queued for a future retry.
class OutboxSyncService {
  final Ref _ref;

  OutboxSyncService(this._ref);

  bool _draining = false;

  Future<void> drainIfSignedIn() async {
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || _draining) return;
    _draining = true;
    try {
      final outbox = _ref.read(syncOutboxDaoProvider);
      final api = _ref.read(authSessionProvider.notifier).api;

      final ops = await outbox.pending();
      for (final op in ops) {
        final resolution = await _resolveCatalogId(api, op.trackId);
        final catalogId = resolution.catalogId;
        if (catalogId == null) {
          // Only malformed/orphaned local operations are discarded. A
          // network or backend failure must never destroy an offline action.
          if (resolution.discard) {
            await outbox.discard(op.id);
            continue;
          }
          return;
        }

        final ok = await _apply(api, op.op, catalogId);
        if (!ok) return;
        await outbox.remove(op.id);
      }
    } finally {
      _draining = false;
    }
  }

  Future<({String? catalogId, bool discard})> _resolveCatalogId(
    BreezzeApi api,
    String externalId,
  ) async {
    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(externalId);
    if (cached != null) return (catalogId: cached, discard: false);

    // Canonical catalog IDs are UUIDs. They do not need to be resolved again.
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(externalId)) {
      return (catalogId: externalId, discard: false);
    }

    final info = await _localTrackInfo(externalId);
    if (info == null) {
      return (catalogId: null, discard: true);
    }

    try {
      final durationMs = info['durationMs'] as int? ?? 0;
      final resolved = await api.resolveCatalogTrack(
        externalId: externalId,
        source: _sourceForExternalId(externalId),
        title: info['title'] as String? ?? '',
        artistName: info['artist'] as String? ?? '',
        durationSec: (durationMs ~/ 1000).clamp(1, 86400),
      );
      final catalogId = resolved['id'] as String?;
      if (catalogId == null || catalogId.isEmpty) {
        return (catalogId: null, discard: false);
      }
      await mapDao.save(externalId, catalogId);
      return (catalogId: catalogId, discard: false);
    } catch (_) {
      // Preserve the outbox item for the next successful connection.
      return (catalogId: null, discard: false);
    }
  }

  String _sourceForExternalId(String id) {
    if (id.startsWith('bzv:')) return 'youtube_music';
    if (id.startsWith('bz:')) {
      final parts = id.split(':');
      if (parts.length >= 3 && parts[1].isNotEmpty) return parts[1];
    }
    return 'breezze_internal';
  }

  /// Display metadata is read only from local rows; it is never treated as
  /// proof that a provider grants playback rights.
  Future<Map<String, Object?>?> _localTrackInfo(String externalId) async {
    final db = _ref.read(breezzeDatabaseProvider);

    final favorite = await (db.select(db.favoriteTracks)
          ..where((t) => t.id.equals(externalId)))
        .getSingleOrNull();
    if (favorite != null) {
      return {
        'title': favorite.title,
        'artist': favorite.artist,
        'durationMs': favorite.durationMs,
      };
    }

    final recent = await (db.select(db.recentlyPlayed)
          ..where((t) => t.id.equals(externalId)))
        .getSingleOrNull();
    if (recent != null) {
      return {
        'title': recent.title,
        'artist': recent.artist,
        'durationMs': recent.durationMs,
      };
    }

    return null;
  }

  Future<bool> _apply(BreezzeApi api, String op, String catalogId) async {
    try {
      switch (op) {
        case 'favorite.add':
          await api.addFavorite(catalogId);
          return true;
        case 'favorite.remove':
          await api.removeFavorite(catalogId);
          return true;
        case 'recent.play':
          // /home/plays is intentionally retired: client-reported plays
          // cannot create qualified ListeningEvents. This endpoint only
          // syncs the user's recent-history list.
          await api.recordRecent(catalogId);
          return true;
        default:
          // Unknown operation types are not retryable.
          return true;
      }
    } catch (_) {
      return false;
    }
  }
}

/// Kept for compatibility with onboarding and download policy consumers.
final outboxTerritoryProvider = StateProvider<String>((ref) => 'WW');

final outboxSyncProvider = Provider<OutboxSyncService>(
  (ref) => OutboxSyncService(ref),
);
