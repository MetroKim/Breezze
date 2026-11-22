import 'package:drift/drift.dart';

import 'breezze_database.dart';

/// Recently played rows use the same account-prefixed local key scheme as
/// favorites so switching accounts cannot reveal another listener's history.
class RecentlyPlayedDao {
  final BreezzeDatabase _db;
  RecentlyPlayedDao(this._db);

  static const _cap = 12;

  String _storageId(String ownerId, String trackId) =>
      ownerId == 'guest' ? trackId : '$ownerId::$trackId';

  String _trackId(String ownerId, String storageId) {
    if (ownerId == 'guest') return storageId;
    return storageId.substring(ownerId.length + 2);
  }

  Future<List<RecentlyPlayedCompanion>> list({
    String ownerId = 'guest',
  }) async {
    final query = _db.select(_db.recentlyPlayed)
      ..orderBy([(t) => OrderingTerm.desc(t.playedAt)]);
    if (ownerId == 'guest') {
      query.where((t) => t.id.notLike('%::%'));
    } else {
      query.where((t) => t.id.like('$ownerId::%'));
    }
    final rows = await query.get();
    return rows
        .map((r) => RecentlyPlayedCompanion.insert(
              id: _trackId(ownerId, r.id),
              title: r.title,
              artist: r.artist,
              artworkUrl: Value(r.artworkUrl),
              durationMs: Value(r.durationMs),
            ))
        .toList();
  }

  Future<void> record({
    required String id,
    required String title,
    required String artist,
    String? artworkUrl,
    int durationMs = 0,
    String ownerId = 'guest',
  }) async {
    final storageId = _storageId(ownerId, id);
    await _db.into(_db.recentlyPlayed).insertOnConflictUpdate(
          RecentlyPlayedCompanion.insert(
            id: storageId,
            title: title,
            artist: artist,
            artworkUrl: Value(artworkUrl),
            durationMs: Value(durationMs),
            playedAt: Value(DateTime.now()),
          ),
        );
    await _trim(ownerId);

    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            op: 'recent.play',
            trackId: storageId,
          ),
        );
  }

  Future<void> _trim(String ownerId) async {
    final query = _db.select(_db.recentlyPlayed)
      ..orderBy([(t) => OrderingTerm.desc(t.playedAt)]);
    if (ownerId == 'guest') {
      query.where((t) => t.id.notLike('%::%'));
    } else {
      query.where((t) => t.id.like('$ownerId::%'));
    }
    final rows = await query.get();
    if (rows.length <= _cap) return;
    final toDelete = rows.skip(_cap).map((r) => r.id).toList();
    await (_db.delete(_db.recentlyPlayed)
          ..where((t) => t.id.isIn(toDelete)))
        .go();
  }
}
