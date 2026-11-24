import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api/breezze_api.dart';

/// Account-scoped album references. Saving metadata never grants playback
/// or download rights for the tracks on the album.
class SavedAlbum {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? catalogUrl;
  final List<String> genres;
  final bool isCompilation;
  final bool isPinned;
  final DateTime addedAt;

  const SavedAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.addedAt,
    this.artworkUrl,
    this.catalogUrl,
    this.genres = const [],
    this.isCompilation = false,
    this.isPinned = false,
  });

  SavedAlbum withPinned(bool pinned) => SavedAlbum(
        id: id,
        title: title,
        artist: artist,
        addedAt: addedAt,
        artworkUrl: artworkUrl,
        catalogUrl: catalogUrl,
        genres: genres,
        isCompilation: isCompilation,
        isPinned: pinned,
      );

  factory SavedAlbum.fromJson(Map<String, dynamic> json) => SavedAlbum(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Unknown album',
        artist: json['artist'] as String? ?? 'Unknown artist',
        artworkUrl: json['artworkUrl'] as String?,
        catalogUrl: json['catalogUrl'] as String?,
        genres: json['genres'] is List
            ? (json['genres'] as List)
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false)
            : const [],
        isCompilation: json['isCompilation'] == true,
        isPinned: json['isPinned'] == true,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// The backend owns bookmark IDs; catalogAlbumId stays the Apple ID.
  factory SavedAlbum.fromServerJson(Map<String, dynamic> json) =>
      SavedAlbum.fromJson({
        'id': json['externalAlbumId'],
        'title': json['title'],
        'artist': json['artist'],
        'artworkUrl': json['artworkUrl'],
        'catalogUrl': json['catalogUrl'],
        'genres': json['genres'],
        'isCompilation': json['isCompilation'],
        'isPinned': json['isPinned'],
        'addedAt': json['savedAt'],
      });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'catalogUrl': catalogUrl,
        'genres': genres,
        'isCompilation': isCompilation,
        'isPinned': isPinned,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };
}

/// Group only verified, stored catalogue metadata: never guess categories
/// from an album title, artist name or unknown streaming provider.
class SavedAlbumGroups {
  static List<String> genres(Iterable<SavedAlbum> albums) {
    final values = <String, String>{};
    for (final album in albums) {
      for (final genre in album.genres) {
        final label = genre.trim();
        if (label.isNotEmpty) {
          values.putIfAbsent(label.toLowerCase(), () => label);
        }
      }
    }
    return values.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  static List<SavedAlbum> forGenre(
    Iterable<SavedAlbum> albums,
    String genre,
  ) {
    final target = genre.trim().toLowerCase();
    return albums
        .where((album) => album.genres.any(
              (value) => value.trim().toLowerCase() == target,
            ))
        .toList(growable: false);
  }

  static List<SavedAlbum> compilations(Iterable<SavedAlbum> albums) =>
      albums.where((album) => album.isCompilation).toList(growable: false);
}

/// Injectable secure key-value seam for deterministic offline/restart tests.
abstract class SavedAlbumKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
}

class _EncryptedSavedAlbumStorage implements SavedAlbumKeyValueStore {
  final FlutterSecureStorage _storage;
  const _EncryptedSavedAlbumStorage(this._storage);

  @override
  Future<String?> read({required String key}) =>
      _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
}

/// Lightweight per-account saved-album cache shared by the Library and
/// album-detail surfaces; the existing signed-in user ID is the owner key.
class SavedAlbumStore {
  final SavedAlbumKeyValueStore _storage;
  SavedAlbumStore({
    FlutterSecureStorage? storage,
    SavedAlbumKeyValueStore? keyValueStore,
  }) : _storage = keyValueStore ??
      _EncryptedSavedAlbumStorage(storage ?? const FlutterSecureStorage());

  static Future<void> _pending = Future<void>.value();

  String _key(String ownerId) {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    return 'breezze:saved_albums:v1:' + Uri.encodeComponent(ownerId);
  }

  String _opsKey(String ownerId) =>
      'breezze:saved_albums:pending:v1:' + Uri.encodeComponent(ownerId);

  String _cloudReadyKey(String ownerId) =>
      'breezze:saved_albums:cloud_ready:v1:' + Uri.encodeComponent(ownerId);

  Future<Map<String, Map<String, dynamic>>> _readOps(String ownerId) async {
    final raw = await _storage.read(key: _opsKey(ownerId));
    if (raw == null) return <String, Map<String, dynamic>>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Corrupt saved album sync outbox');
    }
    return decoded.map((key, value) => MapEntry(
      key.toString(),
      Map<String, dynamic>.from(value as Map),
    ));
  }

  Future<void> _writeOps(
    String ownerId,
    Map<String, Map<String, dynamic>> operations,
  ) async {
    await _storage.write(
      key: _opsKey(ownerId),
      value: jsonEncode(operations),
    );
  }

  Future<List<SavedAlbum>> load(String ownerId) async {
    try {
      final raw = await _storage.read(key: _key(ownerId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final albums = [
        for (final item in decoded)
          if (item is Map)
            SavedAlbum.fromJson(Map<String, dynamic>.from(item)),
      ];
      // Pin ordering is a presentation detail; unpinned albums retain
      // the saved-at order and this never changes catalog identifiers.
      albums.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final byDate = b.addedAt.compareTo(a.addedAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
      return albums;
    } catch (_) {
      // Catalog browsing must still work when local storage is unavailable.
      return [];
    }
  }

  Future<bool> contains(String ownerId, String albumId) async =>
      (await load(ownerId)).any((album) => album.id == albumId);

  Future<void> save(String ownerId, SavedAlbum album) => _serialize(() async {
        final ops = await _readOps(ownerId);
        final albums = await load(ownerId);
        // Album detail may not know an existing pin; metadata refreshes must
        // not clear that user's explicit pin selection.
        final existing = albums.where((item) => item.id == album.id);
        final effective = existing.isEmpty
            ? album
            : album.withPinned(existing.first.isPinned || album.isPinned);
        // Persist intent before updating visible state. Replays are idempotent.
        final explicitPin = ops[album.id]?['pinExplicit'] == true ||
            effective.isPinned;
        ops[album.id] = {
          'action': 'upsert',
          'album': effective.toJson(),
          if (explicitPin) 'pinExplicit': true,
        };
        await _writeOps(ownerId, ops);
        albums.removeWhere((item) => item.id == album.id);
        albums.insert(0, effective);
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(albums.map((item) => item.toJson()).toList()),
        );
      });

  /// Owner-scoped, durable pin/unpin. Uses the existing album upsert journal
  /// so an offline pin cannot race ahead of the album's initial cloud save.
  Future<bool> setPinned(String ownerId, String albumId, bool pinned) =>
      _serialize(() async {
        final albums = await load(ownerId);
        final index = albums.indexWhere((album) => album.id == albumId);
        if (index < 0) return false;
        final original = albums[index];
        if (original.isPinned == pinned) return false;
        final updated = original.withPinned(pinned);
        final ops = await _readOps(ownerId);
        ops[albumId] = {
          'action': 'upsert',
          'album': updated.toJson(),
          'pinExplicit': true,
        };
        await _writeOps(ownerId, ops);
        albums[index] = updated;
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(albums.map((item) => item.toJson()).toList()),
        );
        return true;
      });

  Future<void> remove(String ownerId, String albumId) => _serialize(() async {
        final ops = await _readOps(ownerId);
        ops[albumId] = {'action': 'delete'};
        await _writeOps(ownerId, ops);
        final albums = await load(ownerId);
        albums.removeWhere((item) => item.id == albumId);
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(albums.map((item) => item.toJson()).toList()),
        );
      });

  /// Replays the exact pending user operations, then replaces local cache
  /// with the authoritative account-scoped cloud view. Network failure leaves
  /// both cache and unacknowledged operations intact for the next refresh.
  ///
  /// Existing pre-sync local albums are migrated *once*, without making
  /// remote deletions reappear on every subsequent device login.
  Future<void> syncWithCloud(
    String ownerId,
    BreezzeApi api, {
    required bool Function() ownerStillActive,
  }) => _serialize(() async {
        _key(ownerId); // Require explicit owner; never use shared cache keys.
        final ownerToken = api.accessToken;
        void ensureOwner() {
          if (!ownerStillActive() ||
              ownerToken == null ||
              api.accessToken != ownerToken) {
            throw StateError('Saved album sync owner or token changed');
          }
        }
        ensureOwner();
        final ops = await _readOps(ownerId);
        if (await _storage.read(key: _cloudReadyKey(ownerId)) != 'ready') {
          final legacy = await load(ownerId);
          for (final album in legacy) {
            ops.putIfAbsent(album.id, () => {
              'action': 'upsert',
              'album': album.toJson(),
              if (album.isPinned) 'pinExplicit': true,
            });
          }
          await _writeOps(ownerId, ops);
          // Mark the one-time import after the intents are durable.
          await _storage.write(
            key: _cloudReadyKey(ownerId),
            value: 'ready',
          );
        }

        for (final entry in ops.entries.toList()) {
          ensureOwner();
          final item = entry.value;
          if (item['action'] == 'delete') {
            await api.deleteSavedAlbum(entry.key);
          } else if (item['action'] == 'upsert' && item['album'] is Map) {
            final album = SavedAlbum.fromJson(
              Map<String, dynamic>.from(item['album'] as Map),
            );
            await api.upsertSavedAlbum(
              externalAlbumId: album.id,
              title: album.title,
              artist: album.artist,
              artworkUrl: album.artworkUrl,
              catalogUrl: album.catalogUrl,
              genres: album.genres,
              isCompilation: album.isCompilation,
              // A stale metadata-only save must not overwrite a pin
              // changed on another device since this cache was created.
              isPinned: item['pinExplicit'] == true ? album.isPinned : null,
            );
          } else {
            // Damaged outbox entries must not be silently discarded.
            throw const FormatException('Invalid saved album sync operation');
          }
          ensureOwner();
          ops.remove(entry.key);
          await _writeOps(ownerId, ops);
        }

        final remote = <SavedAlbum>[];
        final seenCursors = <String>{};
        String? cursor;
        // Bounded cursor traversal avoids infinite loops on API errors.
        for (var page = 0; page < 50; page++) {
          ensureOwner();
          final response = await api.getSavedAlbums(cursor: cursor);
          ensureOwner();
          final items = response['items'];
          if (items is! List) {
            throw const FormatException('Invalid saved album API response');
          }
          for (final item in items.whereType<Map>()) {
            final album = Map<String, dynamic>.from(item);
            if (album['source'] != 'apple_itunes') {
              continue;
            }
            remote.add(SavedAlbum.fromServerJson(album));
          }
          final next = response['nextCursor'];
          if (next == null) {
            ensureOwner();
            await _storage.write(
              key: _key(ownerId),
              value: jsonEncode(remote.map((album) => album.toJson()).toList()),
            );
            return;
          }
          if (next is! String || !seenCursors.add(next)) {
            throw const FormatException('Invalid saved album pagination cursor');
          }
          cursor = next;
        }
        throw const FormatException('Saved album catalog exceeds sync page budget');
      });


  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

/// Used to refresh Library after a save/removal from another route.
final savedAlbumRefreshProvider = StateProvider<int>((ref) => 0);

typedef SavedAlbumKey = ({String ownerId, String albumId});

final isAlbumSavedProvider = FutureProvider.family<bool, SavedAlbumKey>(
  (ref, key) => SavedAlbumStore().contains(key.ownerId, key.albumId),
);
