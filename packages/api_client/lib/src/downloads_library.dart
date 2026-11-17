import 'dart:async';
import 'dart:io';

import 'bitchord_adapter.dart';
import 'bz_track.dart';
import 'lyrics_provider.dart';
import 'youtube_source_adapter.dart';

/// Downloads library — offline tracks with lyrics and cover art stored
/// alongside each track (§54.3).
///
/// Layout per track:
///   <downloadsDir>/<trackId>/audio.m4a
///   <downloadsDir>/<trackId>/cover.jpg
///   <downloadsDir>/<trackId>/lyrics.lrc
///   <downloadsDir>/<trackId>/meta.json
class DownloadsLibrary {
  final Directory root;
  final YoutubeSourceAdapter source;
  final LyricsProvider lyrics;

  DownloadsLibrary({
    required this.root,
    required this.source,
    required this.lyrics,
  });

  Directory _dirFor(String trackId) => Directory('${root.path}/$trackId');

  /// Downloads audio + cover art + lyrics for one track.
  Future<bool> download(BzTrack track) async {
    final dir = _dirFor(track.id);
    final videoId =
        track.id.startsWith('bz:') ? track.id.substring(3) : track.id;

    try {
      await dir.create(recursive: true);

      // 1. Audio
      final audioFile = File('${dir.path}/audio.m4a');
      if (!await audioFile.exists()) {
        final sink = audioFile.openWrite();
        try {
          await for (final chunk in source.audioBytes(videoId)) {
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }

      // 2. Cover art
      if (track.artworkUrl != null) {
        final coverFile = File('${dir.path}/cover.jpg');
        if (!await coverFile.exists()) {
          final client = HttpClient();
          try {
            final request = await client.getUrl(Uri.parse(track.artworkUrl!));
            final response = await request.close();
            await response.pipe(coverFile.openWrite());
          } finally {
            client.close();
          }
        }
      }

      // 3. Lyrics (LRCLIB synced when available)
      final lyricsFile = File('${dir.path}/lyrics.lrc');
      final result = await lyrics.bestFor(track);
      if (result != null) {
        await lyricsFile.writeAsString(result.bestLrc);
      }

      // 4. Metadata
      final metaFile = File('${dir.path}/meta.json');
      await metaFile.writeAsString(
          '{"title":"${track.title}","artist":"${track.artist}"}');

      return true;
    } catch (_) {
      return false;
    }
  }

  /// All downloaded tracks with their local assets resolved.
  Future<List<DownloadedTrack>> list() async {
    final tracks = <DownloadedTrack>[];
    if (!await root.exists()) return tracks;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final metaFile = File('${entry.path}/meta.json');
      if (!await metaFile.exists()) continue;
      try {
        final raw = await metaFile.readAsString();
        final title = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(raw);
        final artist = RegExp(r'"artist"\s*:\s*"([^"]*)"').firstMatch(raw);
        tracks.add(DownloadedTrack(
          trackId: entry.uri.pathSegments.last,
          title: title?.group(1) ?? 'Unknown',
          artist: artist?.group(1) ?? 'Unknown',
          audioPath: '${entry.path}/audio.m4a',
          coverPath: await File('${entry.path}/cover.jpg').exists()
              ? '${entry.path}/cover.jpg'
              : null,
          lyricsPath: await File('${entry.path}/lyrics.lrc').exists()
              ? '${entry.path}/lyrics.lrc'
              : null,
        ));
      } catch (_) {
        continue;
      }
    }
    return tracks;
  }

  Future<void> remove(String trackId) async {
    final dir = _dirFor(trackId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// A downloaded track with its local file paths.
class DownloadedTrack {
  final String trackId;
  final String title;
  final String artist;
  final String audioPath;
  final String? coverPath;
  final String? lyricsPath;

  const DownloadedTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.audioPath,
    this.coverPath,
    this.lyricsPath,
  });
}
