import 'package:drift/drift.dart';

import 'breezze_database.dart';

/// Durable, owner-scoped retry records for server playback heartbeats.
/// The session and event identifiers are persisted exactly as sent so a
/// retry after process death remains idempotent.
class PlaybackHeartbeatOutboxDao {
  PlaybackHeartbeatOutboxDao(this._db);

  final BreezzeDatabase _db;

  Future<void> save({
    required String ownerId,
    required String sessionId,
    required String eventId,
    required int sequence,
  }) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO playback_heartbeat_outbox '
      '(owner_id, session_id, event_id, sequence, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [ownerId, sessionId, eventId, sequence, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<List<PlaybackHeartbeatOutboxEntry>> pending({
    required String ownerId,
  }) async {
    final rows = await _db.customSelect(
      'SELECT owner_id, session_id, event_id, sequence '
      'FROM playback_heartbeat_outbox WHERE owner_id = ? ORDER BY created_at ASC',
      variables: [Variable.withString(ownerId)],
    ).get();
    return rows.map((row) => PlaybackHeartbeatOutboxEntry(
      ownerId: row.read<String>('owner_id'),
      sessionId: row.read<String>('session_id'),
      eventId: row.read<String>('event_id'),
      sequence: row.read<int>('sequence'),
    )).toList(growable: false);
  }

  Future<void> remove({
    required String sessionId,
    required String eventId,
  }) async {
    await _db.customStatement(
      'DELETE FROM playback_heartbeat_outbox WHERE session_id = ? AND event_id = ?',
      [sessionId, eventId],
    );
  }

  Future<void> removeSession({
    required String ownerId,
    required String sessionId,
  }) async {
    await _db.customStatement(
      'DELETE FROM playback_heartbeat_outbox WHERE owner_id = ? AND session_id = ?',
      [ownerId, sessionId],
    );
  }
}

class PlaybackHeartbeatOutboxEntry {
  const PlaybackHeartbeatOutboxEntry({
    required this.ownerId,
    required this.sessionId,
    required this.eventId,
    required this.sequence,
  });

  final String ownerId;
  final String sessionId;
  final String eventId;
  final int sequence;
}
