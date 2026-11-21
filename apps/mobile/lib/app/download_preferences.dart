import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persisted offline-download preferences. Rights and available quality are
/// still decided by the backend; these values are user preferences only.
class DownloadPreferences {
  final bool wifiOnly;
  final bool allowCellular;
  final bool autoCleanup;
  final int minimumFreeSpaceGb;
  final String quality;

  const DownloadPreferences({
    this.wifiOnly = true,
    this.allowCellular = false,
    this.autoCleanup = true,
    this.minimumFreeSpaceGb = 2,
    this.quality = 'standard',
  });

  DownloadPreferences copyWith({
    bool? wifiOnly,
    bool? allowCellular,
    bool? autoCleanup,
    int? minimumFreeSpaceGb,
    String? quality,
  }) =>
      DownloadPreferences(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        allowCellular: allowCellular ?? this.allowCellular,
        autoCleanup: autoCleanup ?? this.autoCleanup,
        minimumFreeSpaceGb: minimumFreeSpaceGb ?? this.minimumFreeSpaceGb,
        quality: quality ?? this.quality,
      );

  Map<String, Object> toJson() => {
        'wifiOnly': wifiOnly,
        'allowCellular': allowCellular,
        'autoCleanup': autoCleanup,
        'minimumFreeSpaceGb': minimumFreeSpaceGb,
        'quality': quality,
      };

  factory DownloadPreferences.fromJson(Map<String, dynamic> json) =>
      DownloadPreferences(
        wifiOnly: json['wifiOnly'] as bool? ?? true,
        allowCellular: json['allowCellular'] as bool? ?? false,
        autoCleanup: json['autoCleanup'] as bool? ?? true,
        minimumFreeSpaceGb:
            (json['minimumFreeSpaceGb'] as num?)?.toInt() ?? 2,
        quality: json['quality'] as String? ?? 'standard',
      );
}

class DownloadPreferencesStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory(p.join(dir.path, 'Breezze', 'Preferences'));
    await folder.create(recursive: true);
    return File(p.join(folder.path, 'downloads.json'));
  }

  Future<DownloadPreferences> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const DownloadPreferences();
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const DownloadPreferences();
      return DownloadPreferences.fromJson(json);
    } catch (_) {
      return const DownloadPreferences();
    }
  }

  Future<void> save(DownloadPreferences preferences) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(preferences.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
