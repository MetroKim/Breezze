import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Library section visibility belongs to the signed-in account.
class LibrarySectionPreferencesStore {
  static const sections = <String>{
    'Playlists',
    'Artists',
    'Albums',
    'Songs',
    'Genres',
    'Compilations',
  };
  static const defaultSections = <String>{
    'Playlists',
    'Artists',
    'Albums',
    'Songs',
  };

  final FlutterSecureStorage _storage;
  LibrarySectionPreferencesStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  String _key(String ownerId) =>
      'breezze:library_sections:v1:' + Uri.encodeComponent(ownerId);

  static Set<String> normalize(Iterable<String> values) {
    final valid = values.where(sections.contains).toSet();
    return valid.isEmpty ? Set.of(defaultSections) : valid;
  }

  Future<Set<String>> load(String ownerId) async {
    try {
      final raw = await _storage.read(key: _key(ownerId));
      if (raw == null) return Set.of(defaultSections);
      final decoded = jsonDecode(raw);
      return decoded is List
          ? normalize(decoded.whereType<String>())
          : Set.of(defaultSections);
    } catch (_) {
      return Set.of(defaultSections);
    }
  }

  Future<void> save(String ownerId, Iterable<String> visible) async {
    await _storage.write(
      key: _key(ownerId),
      value: jsonEncode(normalize(visible).toList()..sort()),
    );
  }
}
