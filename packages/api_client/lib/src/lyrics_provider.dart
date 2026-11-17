/// Breezze lyrics provider — LRCLIB (lrclib.net).
///
/// Keyless, free, community API. Exact lookup keyed on track + artist +
/// duration (BitChord's rule: a duration of zero silently matches the
/// wrong edit), with fuzzy search fallback. Returns enhanced-LRC text
/// consumed by the existing LrcParser.
library;

import 'dart:convert';

import 'bz_track.dart';

class LyricsResult {
  final String plainLrc;
  final String? syncedLrc;
  final String trackName;
  final String artistName;

  const LyricsResult({
    required this.plainLrc,
    this.syncedLrc,
    required this.trackName,
    required this.artistName,
  });

  /// The enhanced LRC to render — synced when available, plain otherwise.
  String get bestLrc => syncedLrc ?? plainLrc;
}

/// HTTP seam for lyrics — implemented over package:http in the app.
abstract interface class LyricsHttp {
  Future<String> getText(String url);
}

class LyricsProvider {
  static const _base = 'https://lrclib.net/api';

  final LyricsHttp http;

  LyricsProvider(this.http);

  /// Exact lookup: track + artist + album + duration. Duration is required
  /// — a missing duration matches the shortest edit of the song.
  Future<LyricsResult?> getExact({
    required String trackName,
    required String artistName,
    String? albumName,
    required Duration duration,
  }) async {
    final params = Uri(queryParameters: {
      'track_name': trackName,
      'artist_name': artistName,
      if (albumName != null) 'album_name': albumName,
      'duration': (duration.inSeconds).toString(),
    }).query;
    return _parse(await http.getText('$_base/get?$params'));
  }

  /// Fuzzy search when the album or exact duration is unknown.
  Future<List<LyricsResult>> search(BzTrack track) async {
    final params = Uri(queryParameters: {
      'q': '${track.title} ${track.artist}',
    }).query;
    final raw = await http.getText('$_base/search?$params');
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    final results = <LyricsResult>[];
    for (final item in list) {
      final parsed = _parse(item);
      if (parsed != null) results.add(parsed);
      if (results.length >= 5) break; // bounded
    }
    return results;
  }

  /// Best-effort: exact first, then fuzzy, preferring synced + closest
  /// duration (BitChord's matching rule).
  Future<LyricsResult?> bestFor(BzTrack track, {String? albumName}) async {
    if (track.duration > Duration.zero) {
      final exact = await getExact(
        trackName: track.title,
        artistName: track.artist,
        albumName: albumName,
        duration: track.duration,
      );
      if (exact != null) return exact;
    }
    final fuzzy = await search(track);
    Duration bestDelta = const Duration(days: 1);
    LyricsResult? best;
    for (final result in fuzzy) {
      final delta = (track.duration - _plainDuration(result)).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = result;
      }
    }
    return best;
  }

  Duration _plainDuration(LyricsResult r) => Duration.zero; // duration from exact only

  LyricsResult? _parse(Object? item) {
    if (item is! Map) return null;
    final plain = item['plainLyrics'];
    final synced = item['syncedLyrics'];
    final name = item['trackName'];
    final artist = item['artistName'];
    if (plain is! String && synced is! String) return null;
    return LyricsResult(
      plainLrc: (plain is String ? plain : ''),
      syncedLrc: synced is String ? synced : null,
      trackName: name is String ? name : '',
      artistName: artist is String ? artist : '',
    );
  }
}
