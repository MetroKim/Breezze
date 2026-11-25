import 'dart:convert';
import 'dart:io';

import 'bz_track.dart';
import 'lyrics_provider.dart';

class DownloadCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class DownloadCancelledException implements Exception {}

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
  final LyricsProvider lyrics;

  DownloadsLibrary({
    required this.root,
    required this.lyrics,
  });

  Directory _dirFor(String trackId) {
    final safeTrackId = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (safeTrackId.isEmpty || safeTrackId == '.' || safeTrackId == '..') {
      throw ArgumentError.value(trackId, 'trackId', 'invalid storage key');
    }
    return Directory('${root.path}/$safeTrackId');
  }

  /// Downloads audio + cover art + lyrics for one track.
  ///
  /// [onProgress] receives 0.0–1.0 across the audio transfer (the
  /// dominant cost); lyrics and art are near-instant.
  Future<bool> download(
    BzTrack track, {
    required String downloadUrl,
    required String ownerId,
    required String catalogTrackId,
    required DateTime rightsExpiresAtUtc,
    String assetVariant = 'AAC_256',
    void Function(double progress)? onProgress,
    DownloadCancellation? cancellation,
  }) async {
    if (!rightsExpiresAtUtc.toUtc().isAfter(DateTime.now().toUtc()) ||
        (assetVariant != 'AAC_128' && assetVariant != 'AAC_256')) {
      return false;
    }
    final dir = _dirFor(track.id);
    try {
      await dir.create(recursive: true);
      final audioFile = File('${dir.path}/audio.m4a');
      final metadataFile = File('${dir.path}/meta.json');
      // A pre-existing file is NOT automatically proof of this listener's
      // ownership, source track, rendition or an authorized complete transfer.
      // Do not overwrite metadata to make somebody else's cached bytes appear
      // licensed. Unknown legacy files are preserved but unavailable pending
      // an explicit remove/redownload.
      if (await audioFile.exists()) {
        if (!await metadataFile.exists() || await audioFile.length() == 0) {
          return false;
        }
        final prior = jsonDecode(await metadataFile.readAsString());
        if (prior is! Map<String, dynamic> ||
            prior['ownerId'] != ownerId ||
            prior['catalogTrackId'] != catalogTrackId ||
            prior['assetVariant'] != assetVariant) {
          return false;
        }
      }

      // 1. Fetch only the short-lived URL issued by the backend after its
      // download-rights decision. Never extract media directly from a
      // metadata/search provider in the client.
      await _transferAuthorizedMedia(
        downloadUrl: downloadUrl,
        output: File('${dir.path}/audio.m4a'),
        partial: File('${dir.path}/audio.part'),
        cancellation: cancellation,
        onProgress: onProgress,
        requiredMimeType: 'audio/mp4',
      );
      if (!rightsExpiresAtUtc.toUtc().isAfter(DateTime.now().toUtc())) {
        return false;
      }
      onProgress?.call(1.0);

      // 2. Cover art is optional. A CDN/network failure must not turn a
      // completed, rights-authorized audio download into a failed job.
      if (track.artworkUrl != null) {
        final coverFile = File('${dir.path}/cover.jpg');
        if (!await coverFile.exists()) {
          final client = HttpClient();
          try {
            final request = await client.getUrl(Uri.parse(track.artworkUrl!));
            final response = await request.close();
            if (response.statusCode == HttpStatus.ok) {
              await response.pipe(coverFile.openWrite());
            } else {
              await response.drain<void>();
            }
          } catch (_) {
            if (await coverFile.exists()) await coverFile.delete();
          } finally {
            client.close(force: true);
          }
        }
      }

      // 3. Lyrics are also best-effort. LRCLIB being unavailable must not
      // invalidate an otherwise complete offline audio asset.
      try {
        final lyricsFile = File('${dir.path}/lyrics.lrc');
        final result = await lyrics.bestFor(track);
        if (result != null) {
          await lyricsFile.writeAsString(result.bestLrc);
        }
      } catch (_) {
        // Lyrics can be fetched again independently when the app is online.
      }

      // 4. Ownership and licence metadata are stored beside the app-private asset. Downloads are listed only for their owner and
      // are blocked locally after an explicit rights end time.
      final metaFile = File('${dir.path}/meta.json');
      await metaFile.writeAsString(jsonEncode({
        'title': track.title,
        'artist': track.artist,
        'ownerId': ownerId,
        'catalogTrackId': catalogTrackId,
        'assetVariant': assetVariant,
        'rightsExpiresAtUtc': rightsExpiresAtUtc.toUtc().toIso8601String(),
      }));

      return true;
    } catch (_) {
      return false;
    }
  }

  /// One byte-range transfer implementation shared by audio and licensed
  /// videos. Never receives a URL from an untrusted catalog/search response.
  Future<void> _transferAuthorizedMedia({
    required String downloadUrl,
    required File output,
    required File partial,
    DownloadCancellation? cancellation,
    void Function(double progress)? onProgress,
    String? requiredMimeType,
  }) async {
    if (await output.exists()) {
      onProgress?.call(1.0);
      return;
    }
    final source = Uri.parse(downloadUrl);
    if (source.scheme != 'https' &&
        !(source.scheme == 'http' &&
          (source.host == '127.0.0.1' || source.host == 'localhost'))) {
      throw const HttpException('authorized_media_source_invalid');
    }
    await partial.parent.create(recursive: true);
    final client = HttpClient();
    final validatorFile = File('${partial.path}.etag');
    try {
      var existingBytes = await partial.exists() ? await partial.length() : 0;
      String? storedEtag;
      if (existingBytes > 0 && await validatorFile.exists()) {
        storedEtag = (await validatorFile.readAsString()).trim();
        // Only a strong matching validator authorizes reusing partial bytes.
        if (!RegExp(r'^"[^"]{1,256}"$').hasMatch(storedEtag)) {
          storedEtag = null;
        }
      }
      if (existingBytes > 0 && storedEtag == null) {
        await partial.delete();
        existingBytes = 0;
      }
      final request = await client.getUrl(source);
      if (existingBytes > 0) {
        request.headers.set('range', 'bytes=$existingBytes-');
        request.headers.set('if-range', storedEtag!);
      }
      final response = await request.close();
      final resumes = existingBytes > 0 &&
          response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !resumes) {
        throw HttpException('authorized_download_${response.statusCode}');
      }
      final contentType = response.headers.contentType?.mimeType;
      if (requiredMimeType != null && contentType != requiredMimeType) {
        await response.drain<void>();
        throw const HttpException('authorized_media_type_mismatch');
      }
      final serverEtag = response.headers.value('etag');
      if (resumes) {
        final contentRange = response.headers.value('content-range');
        if (contentRange == null ||
            !contentRange.startsWith('bytes $existingBytes-') ||
            serverEtag != storedEtag) {
          await response.drain<void>();
          throw const HttpException('invalid_resume_content_or_etag');
        }
      } else {
        // A 200 response after If-Range means the media changed. Discard
        // old partial bytes and save a fresh strong validator for retry.
        if (serverEtag != null &&
            RegExp(r'^"[^"]{1,256}"$').hasMatch(serverEtag)) {
          await validatorFile.writeAsString(serverEtag, flush: true);
        } else if (await validatorFile.exists()) {
          await validatorFile.delete();
        }
      }
      final sink = partial.openWrite(mode: resumes ? FileMode.append : FileMode.write);
      var received = resumes ? existingBytes : 0;
      final totalBytes = resumes
          ? _totalBytesFromContentRange(response.headers.value('content-range'))
          : response.contentLength;
      try {
        await for (final chunk in response) {
          if (cancellation?.isCancelled == true) throw DownloadCancelledException();
          sink.add(chunk);
          received += chunk.length;
          if (totalBytes > 0) {
            onProgress?.call((received / totalBytes).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (totalBytes > 0 && received != totalBytes) {
        throw const HttpException('authorized_download_incomplete');
      }
      if (cancellation?.isCancelled == true) throw DownloadCancelledException();
      await partial.rename(output.path);
      if (await validatorFile.exists()) await validatorFile.delete();
      onProgress?.call(1.0);
    } finally {
      client.close(force: true);
    }
  }

  Directory _videoDirFor(String videoAssetId) {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(videoAssetId)) {
      throw ArgumentError.value(videoAssetId, 'videoAssetId', 'invalid video asset key');
    }
    return Directory('${root.path}/videos/$videoAssetId');
  }

  /// Only call after POST /videos/{uuid}/download returns allowed=true.
  /// The saved MP4 is app-private and only playable while its lease is valid.
  Future<bool> downloadVideo({
    required String videoAssetId,
    required String title,
    required String ownerId,
    required String downloadUrl,
    required DateTime rightsExpiresAtUtc,
    DownloadCancellation? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    if (!rightsExpiresAtUtc.toUtc().isAfter(DateTime.now().toUtc())) return false;
    final dir = _videoDirFor(videoAssetId);
    try {
      await dir.create(recursive: true);
      await _transferAuthorizedMedia(
        downloadUrl: downloadUrl,
        output: File('${dir.path}/video.mp4'),
        partial: File('${dir.path}/video.part'),
        cancellation: cancellation,
        onProgress: onProgress,
        requiredMimeType: 'video/mp4',
      );
      if (cancellation?.isCancelled == true) return false;
      await File('${dir.path}/meta.json').writeAsString(jsonEncode({
        'mediaType': 'video',
        'videoAssetId': videoAssetId,
        'title': title,
        'ownerId': ownerId,
        'rightsExpiresAtUtc': rightsExpiresAtUtc.toUtc().toIso8601String(),
      }));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<DownloadedVideo>> listVideos({required String ownerId}) async {
    final folder = Directory('${root.path}/videos');
    if (!await folder.exists()) return [];
    final videos = <DownloadedVideo>[];
    await for (final item in folder.list()) {
      if (item is! Directory) continue;
      final meta = File('${item.path}/meta.json');
      final file = File('${item.path}/video.mp4');
      if (!await meta.exists() || !await file.exists()) continue;
      try {
        final raw = jsonDecode(await meta.readAsString());
        if (raw is! Map<String, dynamic> || raw['mediaType'] != 'video' ||
            raw['ownerId'] != ownerId || raw['videoAssetId'] is! String ||
            item.uri.pathSegments.where((part) => part.isNotEmpty).last != raw['videoAssetId']) {
          continue;
        }
        final expiry = DateTime.tryParse(raw['rightsExpiresAtUtc'] as String? ?? '');
        if (expiry == null) continue;
        videos.add(DownloadedVideo(
          videoAssetId: raw['videoAssetId'] as String,
          ownerId: ownerId,
          title: raw['title'] as String? ?? 'Video',
          filePath: file.path,
          rightsExpiresAtUtc: expiry.toUtc(),
        ));
      } catch (_) {
        continue;
      }
    }
    return videos;
  }

  Future<void> updateVideoOfflineLease(String videoAssetId, DateTime expiresAtUtc) async {
    final meta = File('${_videoDirFor(videoAssetId).path}/meta.json');
    if (!await meta.exists()) return;
    final raw = jsonDecode(await meta.readAsString());
    if (raw is! Map<String, dynamic> || raw['mediaType'] != 'video') return;
    raw['rightsExpiresAtUtc'] = expiresAtUtc.toUtc().toIso8601String();
    await meta.writeAsString(jsonEncode(raw));
  }

  Future<void> removeVideoPartial(String videoAssetId) async {
    final partial = File('${_videoDirFor(videoAssetId).path}/video.part');
    if (await partial.exists()) await partial.delete();
  }

  Future<void> removeVideo(String videoAssetId) async {
    final dir = _videoDirFor(videoAssetId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  int _totalBytesFromContentRange(String? value) {
    if (value == null) return -1;
    final match = RegExp(r'^bytes \d+-\d+/(\d+)$').firstMatch(value);
    return match == null ? -1 : int.tryParse(match.group(1)!) ?? -1;
  }

  Future<void> updateOfflineLease(String trackId, DateTime? expiresAtUtc) async {
    final metaFile = File('${_dirFor(trackId).path}/meta.json');
    if (!await metaFile.exists()) return;
    final raw = jsonDecode(await metaFile.readAsString());
    if (raw is! Map<String, dynamic>) return;
    raw['rightsExpiresAtUtc'] = expiresAtUtc?.toUtc().toIso8601String();
    await metaFile.writeAsString(jsonEncode(raw));
  }

  /// Lists only assets owned by [ownerId]. A legacy file without owner
  /// metadata is deliberately hidden rather than exposed across sessions.
  Future<List<DownloadedTrack>> list({required String ownerId}) async {
    final tracks = <DownloadedTrack>[];
    if (!await root.exists()) return tracks;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final metaFile = File('${entry.path}/meta.json');
      if (!await metaFile.exists()) continue;
      try {
        final raw = jsonDecode(await metaFile.readAsString());
        if (raw is! Map<String, dynamic> || raw['ownerId'] != ownerId) {
          continue;
        }
        final title = raw['title'] as String? ?? 'Unknown';
        final artist = raw['artist'] as String? ?? 'Unknown';
        final catalogTrackId = raw['catalogTrackId'] as String?;
        final audioPath = '${entry.path}/audio.m4a';
        if (catalogTrackId == null || catalogTrackId.isEmpty ||
            !await File(audioPath).exists()) continue;
        final expiryRaw = raw['rightsExpiresAtUtc'] as String?;
        final expiry = expiryRaw == null ? null : DateTime.tryParse(expiryRaw);
        tracks.add(DownloadedTrack(
          trackId: entry.uri.pathSegments.last,
          catalogTrackId: catalogTrackId,
          ownerId: ownerId,
          rightsExpiresAtUtc: expiry?.toUtc(),
          title: title.isNotEmpty ? title : 'Unknown',
          artist: artist,
          audioPath: audioPath,
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

  Future<void> removePartial(String trackId) async {
    final partial = File('${_dirFor(trackId).path}/audio.part');
    if (await partial.exists()) await partial.delete();
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
  /// Storage key used to remove this local asset.
  final String trackId;
  final String catalogTrackId;
  final String ownerId;
  final DateTime? rightsExpiresAtUtc;
  final String title;
  final String artist;
  final String audioPath;
  final String? coverPath;
  final String? lyricsPath;

  const DownloadedTrack({
    required this.trackId,
    required this.catalogTrackId,
    required this.ownerId,
    required this.rightsExpiresAtUtc,
    required this.title,
    required this.artist,
    required this.audioPath,
    this.coverPath,
    this.lyricsPath,
  });
}

class DownloadedVideo {
  final String videoAssetId;
  final String ownerId;
  final String title;
  final String filePath;
  final DateTime rightsExpiresAtUtc;

  const DownloadedVideo({
    required this.videoAssetId,
    required this.ownerId,
    required this.title,
    required this.filePath,
    required this.rightsExpiresAtUtc,
  });
}
