import 'package:drift/drift.dart';

import 'breezze_database.dart';

/// Favorites are stored under account-prefixed local keys. The guest account
/// keeps legacy unprefixed rows; signed-in accounts never read those rows or
/// another account's namespace.
class FavoritesDao {
  final BreezzeDatabase _db;
  FavoritesDao(this._db);

  String _storageId(String ownerId, String trackId) =>
      ownerId == 'guest' ? trackId : '$ownerId::$trackId';

  String _trackId(String ownerId, String storageId) {
    if (ownerId == 'guest') return storageId;
    return storageId.substring(ownerId.length + 2);
  }

  Future<List<FavoriteTracksCompanion>> list({
    String ownerId = 'guest',
  }) async {
    final query = _db.select(_db.favoriteTracks)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (ownerId != 'guest') {
      query.where((t) => t.id.like('$ownerId::%'));
    }
    final fetched = await query.get();
    final rows = ownerId == 'guest'
        ? fetched.where((row) => !row.id.contains('::')).toList()
        : fetched;
    return rows
        .map((r) => FavoriteTracksCompanion.insert(
              id: _trackId(ownerId, r.id),
              title: r.title,
              artist: r.artist,
              artworkUrl: Value(r.artworkUrl),
              durationMs: Value(r.durationMs),
            ))
        .toList();
  }

  Future<void> add({
    required String id,
    required String title,
    required String artist,
    String? artworkUrl,
    int durationMs = 0,
    String ownerId = 'guest',
  }) async {
    final storageId = _storageId(ownerId, id);
    await _db.into(_db.favoriteTracks).insertOnConflictUpdate(
          FavoriteTracksCompanion.insert(
            id: storageId,
            title: title,
            artist: artist,
            artworkUrl: Value(artworkUrl),
            durationMs: Value(durationMs),
          ),
        );
    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            op: 'favorite.add',
            trackId: storageId,
          ),
        );
  }

  Future<void> remove(String id, {String ownerId = 'guest'}) async {
    final storageId = _storageId(ownerId, id);
    await _db.transaction(() async {
      await (_db.delete(_db.favoriteTracks)
            ..where((t) => t.id.equals(storageId)))
          .go();

      // If the add has not reached the server yet, cancel it instead of
      // queuing a remove that would need metadata already deleted locally.
      final pendingAdds = await (_db.select(_db.syncOutbox)
            ..where((t) =>
                t.op.equals('favorite.add') &
                t.trackId.equals(storageId)))
          .get();
      if (pendingAdds.isNotEmpty) {
        final ids = pendingAdds.map((row) => row.id).toList();
        await (_db.delete(_db.syncOutbox)..where((t) => t.id.isIn(ids))).go();
        return;
      }

      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              op: 'favorite.remove',
              trackId: storageId,
            ),
          );
    });
  }

  Future<bool> contains(String id, {String ownerId = 'guest'}) async {
    final storageId = _storageId(ownerId, id);
    final row = await (_db.select(_db.favoriteTracks)
          ..where((t) => t.id.equals(storageId)))
        .getSingleOrNull();
    return row != null;
  }
}
