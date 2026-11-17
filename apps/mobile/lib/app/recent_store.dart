import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Recently-played store — the same JSON persistence pattern as
/// FavoritesStore, capped to the last 12 plays. Drives the Home rails
/// with real history, no fake data (§50.1 audit rule).
class RecentStore {
  static const _fileName = 'breezze_recent.json';
  static const cap = 12;

  final List<RecentEntry> _cache = [];
  bool _loaded = false;

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<RecentEntry>> load() async {
    if (_loaded) return List.unmodifiable(_cache);
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          _cache
            ..clear()
            ..addAll([
              for (final item in raw)
                if (item is Map) RecentEntry.fromJson(item.cast<String, Object?>())
            ]);
        }
      }
    } catch (_) {
      // unreadable file -> empty history
    }
    _loaded = true;
    return List.unmodifiable(_cache);
  }

  Future<void> record(String id, String title, String artist,
      String? artworkUrl, Duration duration) async {
    await load();
    final entry = RecentEntry(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
      durationMs: duration.inMilliseconds,
      playedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _cache
      ..removeWhere((e) => e.id == id)
      ..insert(0, entry);
    if (_cache.length > cap) _cache.removeRange(cap, _cache.length);
    await _save();
  }

  Future<void> _save() async {
    final file = await _file();
    await file.writeAsString(jsonEncode([for (final e in _cache) e.toJson()]));
  }
}

class RecentEntry {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;
  final int playedAtMs;

  const RecentEntry({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
    this.playedAtMs = 0,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
        'playedAtMs': playedAtMs,
      };

  static RecentEntry fromJson(Map<String, Object?> json) => RecentEntry(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
        playedAtMs: json['playedAtMs'] as int? ?? 0,
      );
}
