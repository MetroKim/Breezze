import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Online media metadata returned by the authenticated Breezze API
/// after Commons license verification. The client rechecks the allowlists
/// to avoid accepting arbitrary URLs from search or stale client state.
class CommonsDeviceMedia {
  CommonsDeviceMedia.fromJson(Map<String, dynamic> raw)
      : title = raw['title'] as String? ?? '',
        fileTitle = raw['fileTitle'] as String? ?? '',
        kind = raw['kind'] as String? ?? '',
        mimeType = raw['mimeType'] as String? ?? '',
        bytes = raw['bytes'] as int? ?? 0,
        durationSec = (raw['durationSec'] as num?)?.toDouble(),
        sourceUrl = raw['sourcePage'] as String? ?? '',
        license = raw['license'] as String? ?? '',
        licenseUrl = raw['licenseUrl'] as String? ?? '',
        creator = raw['creator'] as String?,
        streamUrl = raw['streamUrl'] as String? ?? '',
        downloadUrl = raw['downloadUrl'] as String? ?? '',
        downloadAllowed = raw['downloadAllowed'] == true {
    final source = Uri.tryParse(sourceUrl);
    final licenseUri = Uri.tryParse(licenseUrl);
    final validLicense = licenseUri?.scheme == 'https' &&
        licenseUri?.host == 'creativecommons.org' &&
        (RegExp(r'^/publicdomain/zero/1\.0/?$').hasMatch(licenseUri?.path ?? '') ||
            RegExp(r'^/licenses/by(-sa)?/(2\.0|2\.5|3\.0|4\.0)/?$')
                .hasMatch(licenseUri?.path ?? ''));
    final maxBytes = kind == 'video' ? 1000000000 : 250000000;
    final lowerTitle = fileTitle.toLowerCase();
    final genericOgg = mimeType == 'application/ogg' &&
        (kind == 'audio'
            ? lowerTitle.endsWith('.ogg') || lowerTitle.endsWith('.oga')
            : lowerTitle.endsWith('.ogv'));
    if (raw['provider'] != 'wikimedia_commons' ||
        !downloadAllowed ||
        (kind != 'video' && kind != 'audio') ||
        !fileTitle.startsWith('File:') ||
        fileTitle.length > 180 ||
        title.isEmpty ||
        !validLicense ||
        source?.scheme != 'https' ||
        source?.host != 'commons.wikimedia.org' ||
        !_isCommonsUpload(streamUrl) ||
        !_isCommonsUpload(downloadUrl) ||
        (kind == 'audio' && !mimeType.startsWith('audio/') && !genericOgg) ||
        (kind == 'video' && !mimeType.startsWith('video/') && !genericOgg) ||
        bytes <= 0 || bytes > maxBytes ||
        (durationSec != null && (!durationSec!.isFinite || durationSec! <= 0))) {
      throw const FormatException('OPEN_MEDIA_MANIFEST_INVALID');
    }
  }

  final String title;
  final String fileTitle;
  final String kind;
  final String mimeType;
  final int bytes;
  final double? durationSec;
  final String sourceUrl;
  final String license;
  final String licenseUrl;
  final String? creator;
  final String streamUrl;
  final String downloadUrl;
  final bool downloadAllowed;

  static bool _isCommonsUpload(String source) {
    final uri = Uri.tryParse(source);
    return uri?.scheme == 'https' &&
        uri?.host == 'upload.wikimedia.org' &&
        uri?.port == 443 &&
        uri?.userInfo.isEmpty == true &&
        uri?.query.isEmpty == true &&
        uri?.fragment.isEmpty == true &&
        uri!.path.startsWith('/wikipedia/commons/');
  }

  String get extension => switch (mimeType) {
    'audio/mpeg' => 'mp3',
    'audio/ogg' => 'ogg',
    'application/ogg' => kind == 'video' ? 'ogv' : 'ogg',
    'audio/flac' || 'audio/x-flac' => 'flac',
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/webm' => 'webm',
    'audio/mp4' => 'm4a',
    'audio/aac' => 'aac',
    'video/webm' => 'webm',
    'video/ogg' => 'ogv',
    'video/mp4' => 'mp4',
    _ => throw const FormatException('OPEN_MEDIA_CODEC_UNSUPPORTED'),
  };

  Map<String, dynamic> toLocalMetadata() => {
    'provider': 'wikimedia_commons',
    'title': title,
    'fileTitle': fileTitle,
    'kind': kind,
    'mimeType': mimeType,
    'sourcePage': sourceUrl,
    'license': license,
    'licenseUrl': licenseUrl,
    'creator': creator,
    'bytes': bytes,
    'durationSec': durationSec,
    'savedAtUtc': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Persisted open-licensed recording, accessible without an online API call.
class CommonsSavedMedia {
  const CommonsSavedMedia({
    required this.file,
    required this.fileTitle,
    required this.title,
    required this.kind,
    required this.license,
    required this.sourcePage,
    this.creator,
  });

  final File file;
  final String fileTitle;
  final String title;
  final String kind;
  final String license;
  final String sourcePage;
  final String? creator;
}

/// File-by-file device downloads; bypasses the owned-R2 audio store.
/// Do not call with search results: fetch a fresh /resolve result immediately
/// before constructing CommonsDeviceMedia and saving a file.
class CommonsDeviceDownload {
  Future<List<CommonsSavedMedia>> listSaved({required String ownerId}) async {
    if (ownerId.isEmpty || ownerId.length > 128) return [];
    final base = await getApplicationSupportDirectory();
    final ownerKey = sha256.convert(utf8.encode(ownerId)).toString();
    final dir = Directory('${base.path}/Breezze/OpenMedia/$ownerKey');
    if (!await dir.exists()) return [];
    final result = <CommonsSavedMedia>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is! Map<String, dynamic>) continue;
        final fileTitle = raw['fileTitle'] as String?;
        final mime = raw['mimeType'] as String?;
        final kind = raw['kind'] as String?;
        final bytes = raw['bytes'];
        final sourcePage = raw['sourcePage'] as String? ?? '';
        if (fileTitle == null || !fileTitle.startsWith('File:') ||
            fileTitle.length > 180 || mime == null ||
            (kind != 'audio' && kind != 'video') ||
            bytes is! int || bytes <= 0 ||
            (Uri.tryParse(sourcePage)?.host != 'commons.wikimedia.org' ||
             Uri.tryParse(sourcePage)?.scheme != 'https')) continue;
        final extension = switch (mime) {
          'audio/mpeg' => 'mp3',
          'audio/ogg' => 'ogg',
          'application/ogg' => kind == 'video' ? 'ogv' : 'ogg',
          'audio/flac' || 'audio/x-flac' => 'flac',
          'audio/wav' || 'audio/x-wav' => 'wav',
          'audio/webm' => 'webm',
          'audio/mp4' => 'm4a',
          'audio/aac' => 'aac',
          'video/webm' => 'webm',
          'video/ogg' => 'ogv',
          'video/mp4' => 'mp4',
          _ => '',
        };
        if (extension.isEmpty) continue;
        final key = sha256.convert(utf8.encode(fileTitle)).toString();
        if (entity.uri.pathSegments.last != '$key.json') continue;
        final file = File('${dir.path}/$key.$extension');
        if (!await file.exists() || await file.length() != bytes) continue;
        result.add(CommonsSavedMedia(
          file: file, fileTitle: fileTitle,
          title: raw['title'] as String? ?? fileTitle,
          kind: kind, sourcePage: sourcePage,
          license: raw['license'] as String? ?? 'License details saved',
          creator: raw['creator'] as String?,
        ));
      } catch (_) {
        // Corrupt metadata or missing files are not displayed as playable.
      }
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  Future<File> save({
    required CommonsDeviceMedia media,
    required String ownerId,
    void Function(double)? onProgress,
    bool Function()? stillAuthorizedOwner,
  }) async {
    if (ownerId.isEmpty || ownerId.length > 128) {
      throw const FormatException('OPEN_MEDIA_OWNER_INVALID');
    }
    final base = await getApplicationSupportDirectory();
    final ownerKey = sha256.convert(utf8.encode(ownerId)).toString();
    final fileKey = sha256.convert(utf8.encode(media.fileTitle)).toString();
    final dir = Directory('${base.path}/Breezze/OpenMedia/$ownerKey');
    await dir.create(recursive: true);
    final output = File('${dir.path}/$fileKey.${media.extension}');
    final partial = File('${output.path}.part');
    final metadata = File('${dir.path}/$fileKey.json');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      if (await partial.exists()) await partial.delete();
      final request = await client.getUrl(Uri.parse(media.downloadUrl));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const HttpException('OPEN_MEDIA_DOWNLOAD_HTTP_DENIED');
      }
      final returnedType = response.headers.contentType?.mimeType;
      if (returnedType != media.mimeType ||
          (response.contentLength >= 0 && response.contentLength != media.bytes)) {
        await response.drain<void>();
        throw const HttpException('OPEN_MEDIA_DOWNLOAD_CONTENT_MISMATCH');
      }
      var transferred = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response) {
          if (stillAuthorizedOwner?.call() == false) {
            throw const HttpException('OPEN_MEDIA_ACCOUNT_CHANGED');
          }
          transferred += chunk.length;
          if (transferred > media.bytes) {
            throw const HttpException('OPEN_MEDIA_DOWNLOAD_OVERSIZE');
          }
          sink.add(chunk);
          onProgress?.call(transferred / media.bytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (stillAuthorizedOwner?.call() == false) {
        throw const HttpException('OPEN_MEDIA_ACCOUNT_CHANGED');
      }
      if (transferred != media.bytes) {
        throw const HttpException('OPEN_MEDIA_DOWNLOAD_INCOMPLETE');
      }
      if (await output.exists()) await output.delete();
      await partial.rename(output.path);
      await metadata.writeAsString(jsonEncode(media.toLocalMetadata()), flush: true);
      onProgress?.call(1.0);
      return output;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      if (await output.exists() && !await metadata.exists()) await output.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
