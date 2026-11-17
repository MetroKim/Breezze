import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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

@DriftDatabase(tables: [FavoriteTracks, RecentlyPlayed, SyncOutbox])
class BreezzeDatabase extends _$BreezzeDatabase {
  BreezzeDatabase(super.e);

  BreezzeDatabase.open() : super(_openConnection());

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'breezze.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }

  @override
  int get schemaVersion => 1;
}
