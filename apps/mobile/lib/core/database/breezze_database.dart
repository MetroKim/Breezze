import 'package:drift/drift.dart';

import 'database_connection.dart' as connection;

part 'breezze_database.g.dart';

/// Favorites table — mirrors the backend Favorite model.
class FavoriteTracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get artworkUrl => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recently played — capped at 12 rows by the DAO.
class RecentlyPlayed extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get artworkUrl => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get playedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sync outbox — pending writes to replay to the backend once signed
/// in. op: 'favorite.add' | 'favorite.remove' | 'recent.play'.
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get op => text()();
  TextColumn get trackId => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Catalog ID map — external track ID (e.g. bz:<videoId>) to the
/// backend's canonical catalog track ID. Filled by /catalog/resolve
/// during outbox drain; one row per external track, forever.
class CatalogIdMap extends Table {
  TextColumn get externalId => text()();
  TextColumn get catalogId => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {externalId};
}

@DriftDatabase(tables: [FavoriteTracks, RecentlyPlayed, SyncOutbox, CatalogIdMap])
class BreezzeDatabase extends _$BreezzeDatabase {
  BreezzeDatabase(super.e);

  BreezzeDatabase.open() : super(_openConnection());

  static QueryExecutor _openConnection() => connection.createDatabaseConnection();

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('''
            CREATE TABLE playback_heartbeat_outbox (
              owner_id TEXT NOT NULL,
              session_id TEXT NOT NULL,
              event_id TEXT NOT NULL UNIQUE,
              sequence INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              PRIMARY KEY (session_id, sequence)
            )
          ''');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // catalog_id_map table added — existing data untouched.
            await m.createTable(catalogIdMap);
          }
          if (from < 3) {
            await customStatement('''
              CREATE TABLE playback_heartbeat_outbox (
                owner_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                event_id TEXT NOT NULL UNIQUE,
                sequence INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY (session_id, sequence)
              )
            ''');
          }
        },
      );
}
