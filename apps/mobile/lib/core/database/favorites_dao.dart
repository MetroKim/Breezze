import 'package:drift/drift.dart';

import 'breezze_database.dart';

/// Validated canonical favorite from an authorized backend snapshot.
typedef CloudFavoriteRow = ({
  String id,
  String title,
  String artist,
  String? artworkUrl,
  int durationMs,
});

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
    // Local favorite and upload intent must commit atomically. A cloud
    // snapshot can never race between the row insert and its outbox entry.
    await _db.transaction(() async {
      await _db.into(_db.favoriteTracks).insertOnConflictUpdate(
            FavoriteTracksCompanion.insert(
              id: storageId,
              title: title,
              artist: artist,
              artworkUrl: Value(artworkUrl),
              durationMs: Value(durationMs),
            ),
          );
      // Guest favorites never leave the device.
      if (ownerId != 'guest') {
        await _db.into(_db.syncOutbox).insert(
              SyncOutboxCompanion.insert(
                op: 'favorite.add',
                trackId: storageId,
              ),
            );
      }
    });
  }

  Future<void> remove(String id, {String ownerId = 'guest'}) async {
    await _db.transaction(() async {
      final storageId = await _resolvedStorageId(ownerId, id);
      await (_db.delete(_db.favoriteTracks)
            ..where((t) => t.id.equals(storageId)))
          .go();

      if (ownerId == 'guest') return;

      // Always preserve the compensating removal. A queued add may already
      // have been sent to the backend while the user removes this favorite.
      // Cancelling that add here would leave a phantom cloud favorite.
      // The ordered outbox replays add then remove; if the unsent add cannot
      // resolve after its local metadata was deleted, both operations safely
      // become no-ops unless a canonical mapping was already established.
      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              op: 'favorite.remove',
              trackId: storageId,
            ),
          );
    });
  }

  /// Local search results may identify a song by an external source ID,
  /// while the cloud stores the canonical UUID. Resolve that identity only
  /// through the locally remembered source-to-catalog mapping.
  Future<String> _resolvedStorageId(String ownerId, String id) async {
    final directId = _storageId(ownerId, id);
    final direct = await (_db.select(_db.favoriteTracks)
          ..where((t) => t.id.equals(directId)))
        .getSingleOrNull();
    if (direct != null) return directId;
    final mapped = await (_db.select(_db.catalogIdMap)
          ..where((t) => t.externalId.equals(id)))
        .getSingleOrNull();
    if (mapped == null) return directId;
    final catalogId = _storageId(ownerId, mapped.catalogId);
    final canonical = await (_db.select(_db.favoriteTracks)
          ..where((t) => t.id.equals(catalogId)))
        .getSingleOrNull();
    return canonical == null ? directId : catalogId;
  }

  Future<bool> contains(String id, {String ownerId = 'guest'}) async {
    final storageId = await _resolvedStorageId(ownerId, id);
    final row = await (_db.select(_db.favoriteTracks)
          ..where((t) => t.id.equals(storageId)))
        .getSingleOrNull();
    return row != null;
  }

  /// Reconcile an authorized snapshot only if there are NO pending local
  /// writes. Runs as one SQLite transaction, so an offline favorite/delete
  /// cannot be overwritten between the outbox check and replacement.
  ///
  /// Never replace guest data and never enqueue cloud hydration back into
  /// the upload outbox. Other users' local rows remain untouched.
  Future<bool> reconcileCloud({
    required String ownerId,
    required List<CloudFavoriteRow> tracks,
  }) async {
    if (ownerId == 'guest' || ownerId.isEmpty) return false;
    final ownerPrefix = '$ownerId::';
    return _db.transaction(() async {
      final pending = await (_db.select(_db.syncOutbox)
            ..where((t) => t.trackId.like('$ownerPrefix%') &
                (t.op.equals('favorite.add') | t.op.equals('favorite.remove'))))
          .get();
      if (pending.isNotEmpty) return false;

      final local = await (_db.select(_db.favoriteTracks)
            ..where((t) => t.id.like('$ownerPrefix%')))
          .get();
      final localIds = [
        for (final row in local) row.id.substring(ownerPrefix.length),
      ];
      final mappings = localIds.isEmpty
          ? <CatalogIdMapData>[]
          : await (_db.select(_db.catalogIdMap)
                ..where((t) => t.externalId.isIn(localIds)))
              .get();
      final preferredExternal = <String, String>{
        for (final row in mappings) row.catalogId: row.externalId,
      };
      await (_db.delete(_db.favoriteTracks)
            ..where((t) => t.id.like('$ownerPrefix%')))
          .go();
      final seen = <String>{};
      for (final track in tracks) {
        final id = preferredExternal[track.id] ?? track.id;
        if (id.isEmpty || !seen.add(id)) continue;
        await _db.into(_db.favoriteTracks).insertOnConflictUpdate(
              FavoriteTracksCompanion.insert(
                id: _storageId(ownerId, id),
                title: track.title,
                artist: track.artist,
                artworkUrl: Value(track.artworkUrl),
                durationMs: Value(track.durationMs),
              ),
            );
      }
      return true;
    });
  }
}
