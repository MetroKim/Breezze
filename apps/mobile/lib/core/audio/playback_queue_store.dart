import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-isolated, encrypted queue metadata. Grants and media URLs never
/// belong here; restored playback always resolves fresh server permission.
class PlaybackQueueStore {
  PlaybackQueueStore({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String? value)? write,
  })  : _read = read ?? _readSecure,
        _write = write ?? _writeSecure;

  static const _storage = FlutterSecureStorage();
  static const _prefix = 'breezze.playback_queue.v1.';

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String? value) _write;

  static Future<String?> _readSecure(String key) =>
      _storage.read(key: key);

  static Future<void> _writeSecure(String key, String? value) =>
      value == null
          ? _storage.delete(key: key)
          : _storage.write(key: key, value: value);

  String _key(String ownerId) {
    if (ownerId.isEmpty || ownerId.length > 128 ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Invalid queue owner');
    }
    return '$_prefix$ownerId';
  }

  Future<void> save(String ownerId, Map<String, dynamic> snapshot) =>
      _write(_key(ownerId), jsonEncode(snapshot));

  Future<Map<String, dynamic>?> load(String ownerId) async {
    final raw = await _read(_key(ownerId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic> || parsed['v'] != 1) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String ownerId) => _write(_key(ownerId), null);
}
