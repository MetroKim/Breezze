/// Offline media keys live in OS-protected secure storage, per signed-in
/// listener. Never embed the key in Git, app config, metadata or player URLs.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OfflineDeviceKeyStore {
  OfflineDeviceKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static final OfflineDeviceKeyStore shared = OfflineDeviceKeyStore();
  final FlutterSecureStorage _storage;
  final Map<String, Future<SecretKey>> _inFlight = {};

  /// A key may only be generated during an explicitly authorized download.
  /// Playback must set create=false, so loss of the secure keystore fails
  /// closed rather than silently making an unreadable replacement key.
  Future<SecretKey> forOwner(String ownerId, {bool create = false}) {
    if (ownerId.trim().isEmpty) {
      throw StateError('OFFLINE_KEY_OWNER_MISSING');
    }
    final pending = _inFlight[ownerId];
    if (pending != null) return pending;
    final result = _readOrCreate(ownerId, create: create);
    _inFlight[ownerId] = result;
    result.whenComplete(() {
      if (identical(_inFlight[ownerId], result)) _inFlight.remove(ownerId);
    }).ignore();
    return result;
  }

  Future<SecretKey> _readOrCreate(String ownerId, {required bool create}) async {
    final identifier = sha256.convert(utf8.encode(ownerId)).toString();
    final alias = 'breezze.offline.bza8.$identifier';
    final persisted = await _storage.read(key: alias);
    if (persisted != null) {
      try {
        final bytes = base64Url.decode(persisted);
        if (bytes.length == 32) return SecretKey(bytes);
      } catch (_) {
        // A malformed stored key is a hard integrity error; never replace it.
      }
      throw StateError('OFFLINE_KEY_CORRUPT');
    }
    if (!create) throw StateError('OFFLINE_KEY_UNAVAILABLE');

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: alias, value: base64UrlEncode(bytes));
    return SecretKey(bytes);
  }
}
