import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local, device-scoped search history. Search terms are personal UI state,
/// not catalog data, so they stay on this device and are never synced.
class SearchHistoryStore {
  SearchHistoryStore({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFile;

  static const int maxEntries = 10;
  static const String _fileName = 'breezze_search_history.json';

  final Future<File> Function() _fileProvider;

  static Future<File> _defaultFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<String>> load() async {
    try {
      final file = await _fileProvider();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];

      final seen = <String>{};
      final entries = <String>[];
      for (final value in decoded) {
        if (value is! String) continue;
        final query = value.trim();
        if (query.isEmpty || !seen.add(query.toLowerCase())) continue;
        entries.add(query);
        if (entries.length == maxEntries) break;
      }
      return entries;
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<List<String>> add(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return load();

    final current = await load();
    final next = [
      normalized,
      ...current.where(
        (entry) => entry.toLowerCase() != normalized.toLowerCase(),
      ),
    ].take(maxEntries).toList(growable: false);
    await _write(next);
    return next;
  }

  Future<List<String>> remove(String query) async {
    final current = await load();
    final next = current
        .where((entry) => entry.toLowerCase() != query.toLowerCase())
        .toList(growable: false);
    await _write(next);
    return next;
  }

  Future<void> clear() async {
    await _write(const []);
  }

  Future<void> _write(List<String> entries) async {
    final file = await _fileProvider();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(entries), flush: true);
  }
}
