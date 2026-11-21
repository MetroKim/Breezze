import 'dart:convert';
import 'dart:io';

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

/// Local playlist repository. Operations are serialized so rapid adds/removes
/// cannot overwrite each other's JSON snapshots.
class PlaylistStore {
  Future<void> _pending = Future<void>.value();

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

  Future<List<UserPlaylist>> load(String ownerId) async {
    try {
      final file = await _file(ownerId);
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            UserPlaylist.fromJson(item.cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> create(String ownerId, String name) => _serialize(() async {
        final normalized = name.trim();
        if (normalized.isEmpty) {
          throw ArgumentError.value(name, 'name', 'must not be empty');
        }
        final playlists = await load(ownerId);
        playlists.insert(
          0,
          UserPlaylist(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: normalized,
            createdAt: DateTime.now().toUtc(),
            tracks: const [],
          ),
        );
        await _save(ownerId, playlists);
      });

  Future<void> rename(String ownerId, String playlistId, String name) =>
      _serialize(() async {
        final normalized = name.trim();
        if (normalized.isEmpty) {
          throw ArgumentError.value(name, 'name', 'must not be empty');
        }
        final playlists = await load(ownerId);
        final index = playlists.indexWhere((p) => p.id == playlistId);
        if (index < 0) return;
        final old = playlists[index];
        playlists[index] = UserPlaylist(
          id: old.id,
          name: normalized,
          createdAt: old.createdAt,
          tracks: old.tracks,
        );
        await _save(ownerId, playlists);
      });

  Future<void> delete(String ownerId, String playlistId) =>
      _serialize(() async {
        final playlists = await load(ownerId);
        playlists.removeWhere((p) => p.id == playlistId);
        await _save(ownerId, playlists);
      });

  Future<void> addTrack(
    String ownerId,
    String playlistId,
    FavoriteTrack track,
  ) =>
      _serialize(() async {
        final playlists = await load(ownerId);
        final index = playlists.indexWhere((p) => p.id == playlistId);
        if (index < 0) return;
        final old = playlists[index];
        if (old.tracks.any((item) => item.id == track.id)) return;
        playlists[index] = UserPlaylist(
          id: old.id,
          name: old.name,
          createdAt: old.createdAt,
          tracks: [...old.tracks, track],
        );
        await _save(ownerId, playlists);
      });

  Future<void> removeTrack(
    String ownerId,
    String playlistId,
    String trackId,
  ) =>
      _serialize(() async {
        final playlists = await load(ownerId);
        final index = playlists.indexWhere((p) => p.id == playlistId);
        if (index < 0) return;
        final old = playlists[index];
        playlists[index] = UserPlaylist(
          id: old.id,
          name: old.name,
          createdAt: old.createdAt,
          tracks: old.tracks.where((item) => item.id != trackId).toList(),
        );
        await _save(ownerId, playlists);
      });

  Future<void> _save(String ownerId, List<UserPlaylist> playlists) async {
    final file = await _file(ownerId);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}).catchError((_) {});
    return result;
  }
}
