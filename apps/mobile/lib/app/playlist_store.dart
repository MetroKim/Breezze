import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/api/breezze_api.dart';
import '../core/database/catalog_id_map_dao.dart';
import '../core/database/db_instance.dart';

import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap.dart';

/// Signal used by surfaces outside Library after creating or changing a playlist.
final playlistRefreshSignalProvider = StateProvider<int>((ref) => 0);

/// A device-local playlist. Playlist data is isolated by account ID and is
/// never shared between signed-in users on the same device.
class UserPlaylist {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<FavoriteTrack> tracks;

  const UserPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.tracks,
  });

  factory UserPlaylist.fromJson(Map<String, Object?> json) {
    final rawTracks = json['tracks'];
    return UserPlaylist(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled playlist',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tracks: [
        if (rawTracks is List)
          for (final item in rawTracks)
            if (item is Map)
              FavoriteTrack.fromJson(item.cast<String, Object?>()),
      ],
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'tracks': tracks.map((track) => track.toJson()).toList(),
      };
}

/// A single atomic JSON snapshot stores playlist rows AND their unsent edits.
/// Previous releases wrote only a JSON list; that format remains readable.
class _PlaylistDocument {
  final List<UserPlaylist> playlists;
  final List<Map<String, dynamic>> pending;

  _PlaylistDocument(this.playlists, this.pending);
}

/// Account-scoped playlist cache and durable offline mutation journal.
/// No second playlist database: playlist data and its pending edit are
/// committed together by temp-file rename, and replayed in operation order.
class PlaylistStore {
  static Future<void> _pending = Future<void>.value();
  static final Set<String> _syncingOwners = <String>{};
  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<Directory> _directory(String ownerId) async {
    final safeOwner = ownerId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (safeOwner.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must be non-empty');
    }
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/playlists/$safeOwner');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String ownerId) async {
    final directory = await _directory(ownerId);
    return File('${directory.path}/playlists.json');
  }

  Future<_PlaylistDocument> _read(String ownerId) async {
    final file = await _file(ownerId);
    if (!await file.exists()) return _PlaylistDocument([], []);
    final json = jsonDecode(await file.readAsString());
    final List<dynamic> rows;
    final List<dynamic> pending;
    if (json is List) {
      rows = json;
      pending = [];
    } else if (json is Map &&
        json['playlists'] is List &&
        json['pending'] is List) {
      rows = json['playlists'] as List;
      pending = json['pending'] as List;
    } else {
      throw const FormatException('Unsupported playlist store');
    }
    return _PlaylistDocument(
      [
        for (final row in rows)
          if (row is Map)
            UserPlaylist.fromJson(row.cast<String, Object?>()),
      ],
      [
        for (final op in pending)
          if (op is Map)
            Map<String, dynamic>.from(op),
      ],
    );
  }

  Future<List<UserPlaylist>> load(String ownerId) async {
    try {
      return (await _read(ownerId)).playlists;
    } catch (_) {
      // Local filesystem can be unavailable on restricted platforms.
      // Never write a default empty state over an unreadable snapshot.
      return [];
    }
  }

  Future<int> pendingCount(String ownerId, {String? playlistId}) async {
    final doc = await _read(ownerId);
    return playlistId == null
        ? doc.pending.length
        : doc.pending.where((op) => op['playlistId'] == playlistId).length;
  }

  Future<void> _save(String ownerId, _PlaylistDocument doc) async {
    final file = await _file(ownerId);
    final temp = File('${file.path}.tmp');
    final content = jsonEncode({
      'playlists': doc.playlists.map((playlist) => playlist.toJson()).toList(),
      'pending': doc.pending,
    });
    await temp.writeAsString(content, flush: true);
    await temp.rename(file.path);
  }

  void _queue(
    String ownerId,
    _PlaylistDocument doc,
    String type,
    String playlistId, [
    Map<String, dynamic> fields = const {},
  ]) {
    if (ownerId == 'guest') return;
    doc.pending.add({
      'operationId': _newId(),
      'type': type,
      'playlistId': playlistId,
      ...fields,
    });
  }

  Future<void> mergeRemote(
    String ownerId,
    List<Map<String, dynamic>> remote,
  ) => _serialize(() async {
        final doc = await _read(ownerId);
        final pendingIds = {
          for (final entry in doc.pending)
            if (entry['playlistId'] is String)
              entry['playlistId'] as String,
        };
        final local = {for (final item in doc.playlists) item.id: item};
        final merged = <UserPlaylist>[];
        for (final row in remote) {
          final id = row['id'];
          if (id is! String || id.isEmpty) continue;
          if (pendingIds.contains(id)) {
            final offline = local.remove(id);
            if (offline != null) merged.add(offline);
            // A pending delete intentionally keeps this ID absent.
            continue;
          }
          final cached = local.remove(id);
          final rawItems = row['items'];
          final tracks = <FavoriteTrack>[];
          if (rawItems is List) {
            for (final raw in rawItems) {
              if (raw is! Map || raw['track'] is! Map) continue;
              final track = raw['track'] as Map;
              final artist = track['artist'];
              final idValue = track['id'];
              if (idValue is! String || track['title'] is! String) {
                continue;
              }
              tracks.add(FavoriteTrack(
                id: idValue,
                title: track['title'] as String,
                artist: artist is Map && artist['name'] is String
                    ? artist['name'] as String
                    : '',
                durationMs: ((track['duration'] as num?)?.toInt() ?? 0) * 1000,
              ));
            }
          }
          merged.add(UserPlaylist(
            id: id,
            name: row['name'] as String? ?? cached?.name ?? 'Untitled playlist',
            createdAt: DateTime.tryParse(row['createdAt'] as String? ?? '') ??
                cached?.createdAt ?? DateTime.now().toUtc(),
            tracks: rawItems is List ? tracks : (cached?.tracks ?? const []),
          ));
        }
        // A local pending edit wins over a stale server snapshot. Legacy
        // offline drafts from older app versions also survive hydration.
        for (final playlist in local.values) {
          if (pendingIds.contains(playlist.id) ||
              !_uuidPattern.hasMatch(playlist.id)) {
            merged.add(playlist);
          }
        }
        doc.playlists
          ..clear()
          ..addAll(merged);
        await _save(ownerId, doc);
      });

  Future<String> create(String ownerId, String name, {String? id}) =>
      _serialize(() async {
        final normalized = name.trim();
        if (normalized.isEmpty) {
          throw ArgumentError.value(name, 'name', 'must not be empty');
        }
        final doc = await _read(ownerId);
        final playlistId = id ?? _newId();
        if (doc.playlists.any((playlist) => playlist.id == playlistId)) {
          return playlistId;
        }
        doc.playlists.insert(0, UserPlaylist(
          id: playlistId,
          name: normalized,
          createdAt: DateTime.now().toUtc(),
          tracks: const [],
        ));
        _queue(ownerId, doc, 'create', playlistId, {'name': normalized});
        await _save(ownerId, doc);
        return playlistId;
      });

  /// Server hydration may update local items only if there is no unsent
  /// operation for the same playlist. Otherwise an offline add could vanish.
  Future<bool> replaceTracks(
    String ownerId,
    String playlistId,
    List<FavoriteTrack> tracks,
  ) => _serialize(() async {
        final doc = await _read(ownerId);
        if (doc.pending.any((op) => op['playlistId'] == playlistId)) {
          return false;
        }
        final index =
            doc.playlists.indexWhere((playlist) => playlist.id == playlistId);
        if (index < 0) return false;
        final current = doc.playlists[index];
        doc.playlists[index] = UserPlaylist(
          id: current.id,
          name: current.name,
          createdAt: current.createdAt,
          tracks: List<FavoriteTrack>.unmodifiable(tracks),
        );
        await _save(ownerId, doc);
        return true;
      });

  Future<void> rename(String ownerId, String playlistId, String name) =>
      _serialize(() async {
        final normalized = name.trim();
        if (normalized.isEmpty) {
          throw ArgumentError.value(name, 'name', 'must not be empty');
        }
        final doc = await _read(ownerId);
        final index =
            doc.playlists.indexWhere((playlist) => playlist.id == playlistId);
        if (index < 0) return;
        final current = doc.playlists[index];
        doc.playlists[index] = UserPlaylist(
          id: current.id,
          name: normalized,
          createdAt: current.createdAt,
          tracks: current.tracks,
        );
        _queue(ownerId, doc, 'rename', playlistId, {'name': normalized});
        await _save(ownerId, doc);
      });

  Future<void> delete(String ownerId, String playlistId) =>
      _serialize(() async {
        final doc = await _read(ownerId);
        if (!doc.playlists.any((playlist) => playlist.id == playlistId)) return;
        doc.playlists.removeWhere((playlist) => playlist.id == playlistId);
        _queue(ownerId, doc, 'delete', playlistId);
        await _save(ownerId, doc);
      });

  Future<void> addTrack(
    String ownerId,
    String playlistId,
    FavoriteTrack track,
  ) => _serialize(() async {
        final doc = await _read(ownerId);
        final index =
            doc.playlists.indexWhere((playlist) => playlist.id == playlistId);
        if (index < 0) return;
        final current = doc.playlists[index];
        if (current.tracks.any((item) => item.id == track.id)) return;
        doc.playlists[index] = UserPlaylist(
          id: current.id,
          name: current.name,
          createdAt: current.createdAt,
          tracks: [...current.tracks, track],
        );
        _queue(ownerId, doc, 'add', playlistId, {'track': track.toJson()});
        await _save(ownerId, doc);
      });

  Future<void> reorderTracks(
    String ownerId,
    String playlistId,
    int oldIndex,
    int newIndex,
  ) => _serialize(() async {
        final doc = await _read(ownerId);
        final index =
            doc.playlists.indexWhere((playlist) => playlist.id == playlistId);
        if (index < 0) return;
        final current = doc.playlists[index];
        if (oldIndex < 0 || oldIndex >= current.tracks.length ||
            newIndex < 0 || newIndex >= current.tracks.length) {
          return;
        }
        final tracks = List<FavoriteTrack>.from(current.tracks);
        final moved = tracks.removeAt(oldIndex);
        tracks.insert(newIndex, moved);
        doc.playlists[index] = UserPlaylist(
          id: current.id,
          name: current.name,
          createdAt: current.createdAt,
          tracks: tracks,
        );
        _queue(ownerId, doc, 'reorder', playlistId, {
          'tracks': tracks.map((track) => track.toJson()).toList(),
        });
        await _save(ownerId, doc);
      });

  Future<void> removeTrack(
    String ownerId,
    String playlistId,
    String trackId,
  ) => _serialize(() async {
        final doc = await _read(ownerId);
        final index =
            doc.playlists.indexWhere((playlist) => playlist.id == playlistId);
        if (index < 0) return;
        final current = doc.playlists[index];
        final candidate = current.tracks.where((track) => track.id == trackId);
        if (candidate.isEmpty) return;
        final removed = candidate.first;
        doc.playlists[index] = UserPlaylist(
          id: current.id,
          name: current.name,
          createdAt: current.createdAt,
          tracks: current.tracks.where((track) => track.id != trackId).toList(),
        );
        _queue(ownerId, doc, 'remove', playlistId, {'track': removed.toJson()});
        await _save(ownerId, doc);
      });

  /// Import numeric local draft IDs from older versions into stable
  /// client-generated UUIDs. This keeps already-offline playlists uploadable.
  Future<void> _adoptLegacyDrafts(String ownerId) => _serialize(() async {
        final doc = await _read(ownerId);
        var changed = false;
        for (var i = 0; i < doc.playlists.length; i++) {
          final old = doc.playlists[i];
          if (_uuidPattern.hasMatch(old.id)) continue;
          final nextId = _newId();
          doc.playlists[i] = UserPlaylist(
            id: nextId,
            name: old.name,
            createdAt: old.createdAt,
            tracks: old.tracks,
          );
          _queue(ownerId, doc, 'create', nextId, {'name': old.name});
          for (final track in old.tracks) {
            _queue(ownerId, doc, 'add', nextId, {'track': track.toJson()});
          }
          changed = true;
        }
        if (changed) await _save(ownerId, doc);
      });

  Future<String> _canonicalTrackId(
    BreezzeApi api,
    Map<String, dynamic> track,
  ) async {
    final id = track['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Playlist edit has no track ID');
    }
    if (_uuidPattern.hasMatch(id)) return id;
    final map = CatalogIdMapDao(breezzeDb);
    final cached = await map.lookup(id);
    if (cached != null) return cached;
    final title = track['title'];
    final artist = track['artist'];
    if (title is! String || title.isEmpty ||
        artist is! String || artist.isEmpty) {
      throw const FormatException('Missing playlist track metadata');
    }
    String source = 'breezze_internal';
    if (id.startsWith('bzv:')) {
      source = 'youtube_music';
    } else if (id.startsWith('bz:')) {
      final segments = id.split(':');
      if (segments.length >= 3 && segments[1].isNotEmpty) {
        source = segments[1];
      }
    }
    final durationMs = track['durationMs'];
    final resolved = await api.resolveCatalogTrack(
      externalId: id,
      source: source,
      title: title,
      artistName: artist,
      durationSec: ((durationMs is num ? durationMs.toInt() : 0) ~/ 1000)
          .clamp(1, 86400),
    );
    final canonical = resolved['id'];
    if (canonical is! String || !_uuidPattern.hasMatch(canonical)) {
      throw const FormatException('Catalog identity not resolved');
    }
    await map.save(id, canonical);
    return canonical;
  }

  Future<void> _sendOperation(
    BreezzeApi api,
    Map<String, dynamic> operation,
  ) async {
    final id = operation['playlistId'];
    if (id is! String || !_uuidPattern.hasMatch(id)) {
      throw const FormatException('Invalid playlist operation ID');
    }
    switch (operation['type']) {
      case 'create':
        await api.createPlaylist(operation['name'] as String, id: id);
        return;
      case 'rename':
        await api.renamePlaylist(id, operation['name'] as String);
        return;
      case 'delete':
        try {
          await api.deletePlaylist(id);
        } on BreezzeApiException catch (error) {
          if (error.code != 'PLAYLIST_NOT_FOUND') rethrow;
        }
        return;
      case 'add':
        final track = Map<String, dynamic>.from(operation['track'] as Map);
        await api.addPlaylistTrack(id, await _canonicalTrackId(api, track));
        return;
      case 'remove':
        final track = Map<String, dynamic>.from(operation['track'] as Map);
        await api.removePlaylistTrack(id, await _canonicalTrackId(api, track));
        return;
      case 'reorder':
        final tracks = operation['tracks'] as List;
        final ids = <String>[];
        for (final item in tracks) {
          ids.add(await _canonicalTrackId(
            api, Map<String, dynamic>.from(item as Map),
          ));
        }
        await api.reorderPlaylistTracks(id, ids);
        return;
      default:
        throw const FormatException('Unknown playlist operation');
    }
  }

  /// Replay durable operations in strict order. A network error, mismatched
  /// playlist membership, or permission denial leaves the operation pending.
  /// Only a confirmed server response deletes a journal entry.
  Future<bool> syncOwner(
    String ownerId,
    BreezzeApi api, {
    required bool Function() ownerStillActive,
  }) async {
    if (ownerId == 'guest' || !ownerStillActive() ||
        !_syncingOwners.add(ownerId)) return false;
    try {
      await _adoptLegacyDrafts(ownerId);
      while (ownerStillActive()) {
        final doc = await _read(ownerId);
        if (doc.pending.isEmpty) return true;
        final operation = doc.pending.first;
        try {
          await _sendOperation(api, operation);
        } catch (_) {
          // Never discard an edit just because the server is offline or
          // another device changed playlist membership meanwhile.
          return false;
        }
        if (!ownerStillActive()) return false;
        await _serialize(() async {
          final current = await _read(ownerId);
          if (current.pending.isNotEmpty &&
              current.pending.first['operationId'] ==
                  operation['operationId']) {
            current.pending.removeAt(0);
            await _save(ownerId, current);
          }
        });
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _syncingOwners.remove(ownerId);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}).catchError((_) {});
    return result;
  }
}
