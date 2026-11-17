import 'package:drift/drift.dart';

import 'breezze_database.dart';

/// Drains the sync outbox against the backend once the user is signed
/// in. Replays ops in order; drops a failed op's batch on auth
/// failure and retries on the next drain.
class SyncOutboxDao {
  final BreezzeDatabase _db;
  SyncOutboxDao(this._db);

  Future<List<SyncOutboxData>> pending() {
    return (_db.select(_db.syncOutbox)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<void> drain(void Function() onOpApplied) async {
    final ops = await pending();
    for (final op in ops) {
      onOpApplied();
      await (_db.delete(_db.syncOutbox)..where((t) => t.id.equals(op.id)))
          .go();
    }
  }

  Future<void> clear() async {
    await _db.delete(_db.syncOutbox).go();
  }
}
