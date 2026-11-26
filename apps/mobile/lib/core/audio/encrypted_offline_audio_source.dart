/// An encrypted, seekable native audio source for Breezze offline tracks.
 ///
 /// Decrypts authenticated AES-GCM chunks into memory only as just_audio
 /// requests byte ranges. No temporary plaintext audio file is created.
 /// This supplies application encryption, not provider DRM certification.
library;

import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'offline_device_key.dart';

class BreezzeEncryptedOfflineAudioSource extends ja.StreamAudioSource {
  BreezzeEncryptedOfflineAudioSource._({
    required File file,
    required BreezzeOfflineAudioCipher cipher,
    required String ownerId,
    required String catalogTrackId,
    required String? assetVersion,
    required DateTime rightsExpiresAtUtc,
    required int size,
  }) : _file = file,
       _cipher = cipher,
       _ownerId = ownerId,
       _catalogTrackId = catalogTrackId,
       _assetVersion = assetVersion,
       _rightsExpiresAtUtc = rightsExpiresAtUtc,
       _size = size;

  final File _file;
  final BreezzeOfflineAudioCipher _cipher;
  final String _ownerId;
  final String _catalogTrackId;
  final String? _assetVersion;
  final DateTime _rightsExpiresAtUtc;
  final int _size;

  /// Check owner and lease before touching the device keystore. A caller
  /// cannot spoof the selected account via a local file path.
  static Future<BreezzeEncryptedOfflineAudioSource> open({
    required String path,
    required String signedInUserId,
    OfflineDeviceKeyStore? keyStore,
  }) async {
    if (!path.endsWith('/audio.bza') && !path.endsWith('\\audio.bza')) {
      throw StateError('ENCRYPTED_MEDIA_PATH_INVALID');
    }
    final file = File(path);
    final metaFile = File('${file.parent.path}/meta.json');
    final raw = jsonDecode(await metaFile.readAsString());
    if (raw is! Map<String, dynamic> ||
        raw['storageFormat'] != 'bza8' ||
        raw['ownerId'] != signedInUserId ||
        signedInUserId.isEmpty) {
      throw StateError('OFFLINE_ACCOUNT_MISMATCH');
    }
    final trackId = raw['catalogTrackId'] as String?;
    final expiry = DateTime.tryParse(raw['rightsExpiresAtUtc'] as String? ?? '');
    if (trackId == null || trackId.isEmpty ||
        expiry == null || !expiry.toUtc().isAfter(DateTime.now().toUtc())) {
      throw StateError('OFFLINE_LICENSE_INVALID');
    }
    final key = await (keyStore ?? OfflineDeviceKeyStore.shared)
        .forOwner(signedInUserId, create: false);
    final cipher = BreezzeOfflineAudioCipher(key);
    final size = await cipher.plaintextLength(file);
    return BreezzeEncryptedOfflineAudioSource._(
      file: file,
      cipher: cipher,
      ownerId: signedInUserId,
      catalogTrackId: trackId,
      assetVersion: raw['assetVersion'] as String?,
      rightsExpiresAtUtc: expiry.toUtc(),
      size: size,
    );
  }

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    if (!_rightsExpiresAtUtc.isAfter(DateTime.now().toUtc())) {
      throw StateError('OFFLINE_LICENSE_EXPIRED');
    }
    final from = start ?? 0;
    final until = end ?? _size;
    if (from < 0 || until < from || until > _size) {
      throw RangeError('Offline audio requested out of bounds');
    }
    return ja.StreamAudioResponse(
      sourceLength: _size,
      contentLength: until - from,
      offset: from,
      contentType: 'audio/mp4',
      stream: _cipher.decryptRange(
        encrypted: _file,
        ownerId: _ownerId,
        catalogTrackId: _catalogTrackId,
        assetVersion: _assetVersion,
        start: from,
        end: until,
      ),
    );
  }
}
