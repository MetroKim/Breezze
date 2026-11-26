import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
    DateTime? rightsExpiresAtUtc,
    String? assetVersion,
    void Function(double progress)? onProgress,
    DownloadCancellation? cancellation,
  }) async {
    final dir = _dirFor(track.id);
    try {
      await dir.create(recursive: true);

      // An existing file or resumable fragment must represent this exact
      // *authorized asset version* and owner, not an older recording/lease.
      // An absent version is deliberately non-resumable: an HTTP range on a
      // different rendition can silently produce corrupt playable bytes.
      final output = File('${dir.path}/audio.m4a');
      final partial = File('${dir.path}/audio.part');
      final fragmentIdentity = File('${dir.path}/audio.part.identity.json');
      final metaFile = File('${dir.path}/meta.json');
      if (await output.exists()) {
        var sameAsset = false;
        if (assetVersion != null && await metaFile.exists()) {
          try {
            final raw = jsonDecode(await metaFile.readAsString());
            sameAsset = raw is Map &&
                raw['ownerId'] == ownerId &&
                raw['catalogTrackId'] == catalogTrackId &&
                raw['assetVersion'] == assetVersion;
          } catch (_) {
            sameAsset = false;
          }
        }
        if (!sameAsset) await output.delete();
      }
      if (await partial.exists()) {
        var sameFragment = false;
        if (assetVersion != null && await fragmentIdentity.exists()) {
          try {
            final raw = jsonDecode(await fragmentIdentity.readAsString());
            sameFragment = raw is Map &&
                raw['ownerId'] == ownerId &&
                raw['catalogTrackId'] == catalogTrackId &&
                raw['assetVersion'] == assetVersion;
          } catch (_) {
            sameFragment = false;
          }
        }
        if (!sameFragment) await partial.delete();
      }
      if (assetVersion != null && !await output.exists()) {
        await fragmentIdentity.writeAsString(jsonEncode({
          'ownerId': ownerId,
          'catalogTrackId': catalogTrackId,
          'assetVersion': assetVersion,
        }), flush: true);
      }

      // 1. Fetch only the short-lived URL issued by the backend after its
      // download-rights decision. Never extract media directly from a
      // metadata/search provider in the client.
      await _transferAuthorizedMedia(
        downloadUrl: downloadUrl,
        output: output,
        partial: partial,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      // Only an actual SHA256 digest authorizes reusing downloaded bytes.
      // A corrupt/mixed file is deleted before it can become an offline
      // playable asset or appear as a successful completed download.
      if (assetVersion != null &&
          RegExp(r'^[0-9a-fA-F]{64}

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
      await metaFile.writeAsString(jsonEncode({
        'title': track.title,
        'artist': track.artist,
        'ownerId': ownerId,
        'catalogTrackId': catalogTrackId,
        'assetVersion': assetVersion,
        'rightsExpiresAtUtc': rightsExpiresAtUtc?.toUtc().toIso8601String(),
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
    try {
      final existingBytes = await partial.exists() ? await partial.length() : 0;
      final request = await client.getUrl(source);
      if (existingBytes > 0) {
        request.headers.set('range', 'bytes=$existingBytes-');
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
      if (resumes) {
        final contentRange = response.headers.value('content-range');
        final match = contentRange == null ? null
            : RegExp(r'^bytes (\d+)-(\d+)/(\d+)
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
).firstMatch(contentRange);
        final start = match == null ? null : int.tryParse(match.group(1)!);
        final end = match == null ? null : int.tryParse(match.group(2)!);
        final total = match == null ? null : int.tryParse(match.group(3)!);
        final receivedLength = response.contentLength;
        if (start != existingBytes || end == null || total == null ||
            end < start! || total <= end ||
            (receivedLength >= 0 && receivedLength != end - start! + 1)) {
          await response.drain<void>();
          throw const HttpException('invalid_resume_content_range');
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
).hasMatch(assetVersion)) {
        final actual = await sha256.bind(output.openRead()).first;
        if (actual.toString().toLowerCase() != assetVersion.toLowerCase()) {
          await output.delete();
          throw const HttpException('authorized_media_sha256_mismatch');
        }
      }
      if (await fragmentIdentity.exists()) await fragmentIdentity.delete();
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
      await metaFile.writeAsString(jsonEncode({
        'title': track.title,
        'artist': track.artist,
        'ownerId': ownerId,
        'catalogTrackId': catalogTrackId,
        'assetVersion': assetVersion,
        'rightsExpiresAtUtc': rightsExpiresAtUtc?.toUtc().toIso8601String(),
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
    try {
      final existingBytes = await partial.exists() ? await partial.length() : 0;
      final request = await client.getUrl(source);
      if (existingBytes > 0) {
        request.headers.set('range', 'bytes=$existingBytes-');
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
      if (resumes) {
        final contentRange = response.headers.value('content-range');
        final match = contentRange == null ? null
            : RegExp(r'^bytes (\d+)-(\d+)/(\d+)
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
).firstMatch(contentRange);
        final start = match == null ? null : int.tryParse(match.group(1)!);
        final end = match == null ? null : int.tryParse(match.group(2)!);
        final total = match == null ? null : int.tryParse(match.group(3)!);
        final receivedLength = response.contentLength;
        if (start != existingBytes || end == null || total == null ||
            end < start! || total <= end ||
            (receivedLength >= 0 && receivedLength != end - start! + 1)) {
          await response.drain<void>();
          throw const HttpException('invalid_resume_content_range');
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
