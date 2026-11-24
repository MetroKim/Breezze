import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api/breezze_api.dart';
import 'saved_album_store.dart';

/// A verified catalog artist followed by one account. This is library
/// metadata only: it never grants content playback or download permissions.
class FollowedArtist {
  final String artistKey;
  final String displayName;
  final bool isPinned;
  final DateTime followedAt;

  const FollowedArtist({
    required this.artistKey,
    required this.displayName,
    required this.followedAt,
    this.isPinned = false,
  });

  FollowedArtist withPinned(bool pinned) => FollowedArtist(
        artistKey: artistKey,
        displayName: displayName,
        followedAt: followedAt,
        isPinned: pinned,
      );

  factory FollowedArtist.fromJson(Map<String, dynamic> row) {
    final key = row['artistKey'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('Missing followed artist key');
    }
    final label = row['displayName'];
    return FollowedArtist(
      artistKey: key,
      displayName: label is String && label.trim().isNotEmpty
          ? label.trim()
          : key,
      isPinned: row['isPinned'] == true,
      followedAt: DateTime.tryParse(row['followedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'artistKey': artistKey,
        'displayName': displayName,
        'isPinned': isPinned,
        'followedAt': followedAt.toUtc().toIso8601String(),
      };
}

class _EncryptedFollowedArtistStorage implements SavedAlbumKeyValueStore {
  final FlutterSecureStorage storage;
  const _EncryptedFollowedArtistStorage(this.storage);

  @override
  Future<String?> read({required String key}) => storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      storage.write(key: key, value: value);
}

/// Reuses the same secure owner-scoped storage abstraction as album bookmarks.
/// Every offline change is journaled before the visible cache is updated.
class FollowedArtistStore {
  final SavedAlbumKeyValueStore _storage;

  FollowedArtistStore({
    FlutterSecureStorage? storage,
    SavedAlbumKeyValueStore? keyValueStore,
  }) : _storage = keyValueStore ??
            _EncryptedFollowedArtistStorage(
              storage ?? const FlutterSecureStorage(),
            );

  static Future<void> _pending = Future<void>.value();

  String _ownerKey(String ownerId) {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    return Uri.encodeComponent(ownerId);
  }

  String _key(String ownerId) =>
      'breezze:followed_artists:v1:' + _ownerKey(ownerId);
  String _opsKey(String ownerId) =>
      'breezze:followed_artists:pending:v1:' + _ownerKey(ownerId);

  Future<Map<String, Map<String, dynamic>>> _readOps(String ownerId) async {
    final raw = await _storage.read(key: _opsKey(ownerId));
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid followed artist outbox');
    }
    return decoded.map((key, value) => MapEntry(
          key.toString(),
          Map<String, dynamic>.from(value as Map),
        ));
  }

  Future<void> _writeOps(
    String ownerId,
    Map<String, Map<String, dynamic>> ops,
  ) =>
      _storage.write(key: _opsKey(ownerId), value: jsonEncode(ops));

  Future<List<FollowedArtist>> load(String ownerId) async {
    final raw = await _storage.read(key: _key(ownerId));
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid followed artist cache');
    }
    final artists = [
      for (final item in decoded)
        FollowedArtist.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    artists.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byDate = b.followedAt.compareTo(a.followedAt);
      return byDate != 0
          ? byDate
          : a.artistKey.compareTo(b.artistKey);
    });
    return artists;
  }

  Future<FollowedArtist?> find(String ownerId, String artistKey) async {
    final rows = await load(ownerId);
    for (final row in rows) {
      if (row.artistKey == artistKey) return row;
    }
    return null;
  }

  Future<int> pendingCount(String ownerId) async =>
      (await _readOps(ownerId)).length;

  Future<void> follow(String ownerId, String key, String name) =>
      _serialize(() async {
        if (!RegExp(r'^(apple:[0-9]{1,20}|catalog:[a-zA-Z0-9_-]{1,128})$')
                .hasMatch(key) ||
            name.trim().isEmpty || name.trim().length > 200) {
          throw ArgumentError('Invalid artist identity or name');
        }
        final rows = await load(ownerId);
        final existing = rows.where((row) => row.artistKey == key);
        final artist = FollowedArtist(
          artistKey: key,
          displayName: name.trim(),
          followedAt: existing.isEmpty
              ? DateTime.now().toUtc()
              : existing.first.followedAt,
          isPinned: existing.isNotEmpty && existing.first.isPinned,
        );
        final ops = await _readOps(ownerId);
        ops[key] = {
          'action': 'follow',
          'artist': artist.toJson(),
          if (ops[key]?['pinExplicit'] == true) 'pinExplicit': true,
        };
        await _writeOps(ownerId, ops);
        rows.removeWhere((row) => row.artistKey == key);
        rows.add(artist);
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(rows.map((item) => item.toJson()).toList()),
        );
      });

  Future<void> unfollow(String ownerId, String key) =>
      _serialize(() async {
        final rows = await load(ownerId);
        final ops = await _readOps(ownerId);
        ops[key] = {'action': 'unfollow'};
        await _writeOps(ownerId, ops);
        rows.removeWhere((row) => row.artistKey == key);
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(rows.map((item) => item.toJson()).toList()),
        );
      });

  Future<bool> setPinned(String ownerId, String key, bool pinned) =>
      _serialize(() async {
        final rows = await load(ownerId);
        final index = rows.indexWhere((row) => row.artistKey == key);
        if (index < 0 || rows[index].isPinned == pinned) return false;
        final updated = rows[index].withPinned(pinned);
        final ops = await _readOps(ownerId);
        ops[key] = {
          'action': 'follow',
          'artist': updated.toJson(),
          'pinExplicit': true,
        };
        await _writeOps(ownerId, ops);
        rows[index] = updated;
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(rows.map((item) => item.toJson()).toList()),
        );
        return true;
      });

  /// Replays account-owned pending changes before reading cloud state. Re-POST
  /// of an already followed artist is idempotent and never resets its pin.
  Future<void> syncWithCloud(
    String ownerId,
    BreezzeApi api, {
    required bool Function() ownerStillActive,
  }) =>
      _serialize(() async {
        _ownerKey(ownerId);
        final token = api.accessToken;
        void ensureOwner() {
          if (!ownerStillActive() || token == null ||
              api.accessToken != token) {
            throw StateError('Followed artist sync identity changed');
          }
        }

        ensureOwner();
        final ops = await _readOps(ownerId);
        for (final entry in ops.entries.toList()) {
          ensureOwner();
          final operation = entry.value;
          if (operation['action'] == 'unfollow') {
            await api.followArtist(entry.key, false);
          } else if (operation['action'] == 'follow' &&
              operation['artist'] is Map) {
            final artist = FollowedArtist.fromJson(
              Map<String, dynamic>.from(operation['artist'] as Map),
            );
            await api.followArtist(
              entry.key, true, displayName: artist.displayName,
            );
            if (operation['pinExplicit'] == true) {
              await api.pinArtist(entry.key, artist.isPinned);
            }
          } else {
            throw const FormatException('Invalid followed artist operation');
          }
          ensureOwner();
          ops.remove(entry.key);
          await _writeOps(ownerId, ops);
        }

        ensureOwner();
        final response = await api.getFollowedArtists();
        final remote = response['items'];
        if (remote is! List) {
          throw const FormatException('Invalid followed artist response');
        }
        final rows = <FollowedArtist>[];
        for (final item in remote) {
          if (item is! Map) {
            throw const FormatException('Invalid cloud artist record');
          }
          rows.add(FollowedArtist.fromJson(
            Map<String, dynamic>.from(item),
          ));
        }
        ensureOwner();
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(rows.map((item) => item.toJson()).toList()),
        );
      });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}
