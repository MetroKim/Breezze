import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  });

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
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'catalogUrl': catalogUrl,
        'genres': genres,
        'isCompilation': isCompilation,
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

/// Lightweight per-account saved-album cache shared by the Library and
/// album-detail surfaces; the existing signed-in user ID is the owner key.
class SavedAlbumStore {
  final FlutterSecureStorage _storage;
  SavedAlbumStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static Future<void> _pending = Future<void>.value();

  String _key(String ownerId) {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    return 'breezze:saved_albums:v1:' + Uri.encodeComponent(ownerId);
  }

  Future<List<SavedAlbum>> load(String ownerId) async {
    try {
      final raw = await _storage.read(key: _key(ownerId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            SavedAlbum.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      // Catalog browsing must still work when local storage is unavailable.
      return [];
    }
  }

  Future<bool> contains(String ownerId, String albumId) async =>
      (await load(ownerId)).any((album) => album.id == albumId);

  Future<void> save(String ownerId, SavedAlbum album) => _serialize(() async {
        final albums = await load(ownerId);
        albums.removeWhere((item) => item.id == album.id);
        albums.insert(0, album);
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(albums.map((item) => item.toJson()).toList()),
        );
      });

  Future<void> remove(String ownerId, String albumId) => _serialize(() async {
        final albums = await load(ownerId);
        albums.removeWhere((item) => item.id == albumId);
        await _storage.write(
          key: _key(ownerId),
          value: jsonEncode(albums.map((item) => item.toJson()).toList()),
        );
      });

  Future<void> _serialize(Future<void> Function() action) {
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
