import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Durable, account-scoped checkpoint for one server playback session.
///
/// The event ID and sequence are persisted before transmission. Retrying the
/// same pair is safe because the API treats heartbeat event IDs idempotently.
class PlaybackHeartbeatCheckpoint {
  const PlaybackHeartbeatCheckpoint({
    required this.ownerId,
    required this.sessionId,
    required this.sequence,
    this.pendingEventId,
  });

  final String ownerId;
  final String sessionId;
  final int sequence;
  final String? pendingEventId;

  Map<String, Object?> toJson() => {
        'ownerId': ownerId,
        'sessionId': sessionId,
        'sequence': sequence,
        'pendingEventId': pendingEventId,
      };

  factory PlaybackHeartbeatCheckpoint.fromJson(Map<String, dynamic> json) {
    final ownerId = json['ownerId'];
    final sessionId = json['sessionId'];
    final sequence = json['sequence'];
    final eventId = json['pendingEventId'];
    if (ownerId is! String ||
        ownerId.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty ||
        sequence is! int ||
        sequence < 1 ||
        (eventId != null && eventId is! String)) {
      throw const FormatException('Invalid playback heartbeat checkpoint');
    }
    return PlaybackHeartbeatCheckpoint(
      ownerId: ownerId,
      sessionId: sessionId,
      sequence: sequence,
      pendingEventId: eventId as String?,
    );
  }
}

abstract interface class PlaybackHeartbeatStore {
  Future<PlaybackHeartbeatCheckpoint?> read(String ownerId, String sessionId);
  Future<List<PlaybackHeartbeatCheckpoint>> pendingForOwner(String ownerId);
  Future<void> write(PlaybackHeartbeatCheckpoint checkpoint);
  Future<void> clear(String ownerId, String sessionId);
}

class SecurePlaybackHeartbeatStore implements PlaybackHeartbeatStore {
  SecurePlaybackHeartbeatStore(this._storage);

  static const _prefix = 'breezze.playback.heartbeat.';
  final FlutterSecureStorage _storage;

  String _key(String ownerId, String sessionId) =>
      '$_prefix$ownerId.$sessionId';

  @override
  Future<PlaybackHeartbeatCheckpoint?> read(
    String ownerId,
    String sessionId,
  ) async {
    final raw = await _storage.read(key: _key(ownerId, sessionId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final checkpoint = PlaybackHeartbeatCheckpoint.fromJson(decoded);
      if (checkpoint.ownerId != ownerId || checkpoint.sessionId != sessionId) {
        throw const FormatException();
      }
      return checkpoint;
    } catch (_) {
      // Corrupt secure-storage state must not block playback forever.
      await clear(ownerId, sessionId);
      return null;
    }
  }

  @override
  Future<List<PlaybackHeartbeatCheckpoint>> pendingForOwner(
    String ownerId,
  ) async {
    final all = await _storage.readAll();
    final prefix = '$_prefix$ownerId.';
    final checkpoints = <PlaybackHeartbeatCheckpoint>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is! Map<String, dynamic>) continue;
        final checkpoint = PlaybackHeartbeatCheckpoint.fromJson(decoded);
        if (checkpoint.ownerId == ownerId &&
            entry.key == _key(ownerId, checkpoint.sessionId) &&
            checkpoint.pendingEventId != null) {
          checkpoints.add(checkpoint);
        }
      } catch (_) {
        await _storage.delete(key: entry.key);
      }
    }
    return checkpoints;
  }

  @override
  Future<void> write(PlaybackHeartbeatCheckpoint checkpoint) =>
      _storage.write(
        key: _key(checkpoint.ownerId, checkpoint.sessionId),
        value: jsonEncode(checkpoint.toJson()),
      );

  @override
  Future<void> clear(String ownerId, String sessionId) =>
      _storage.delete(key: _key(ownerId, sessionId));
}

final playbackHeartbeatStoreProvider = Provider<PlaybackHeartbeatStore>(
  (ref) => SecurePlaybackHeartbeatStore(const FlutterSecureStorage()),
);
