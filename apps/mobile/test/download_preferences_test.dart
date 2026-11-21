import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/app/download_preferences.dart';

void main() {
  group('DownloadPreferences.fromJson', () {
    test('uses defaults for missing fields', () {
      final value = DownloadPreferences.fromJson({});
      expect(value.wifiOnly, isTrue);
      expect(value.allowCellular, isFalse);
      expect(value.autoCleanup, isTrue);
      expect(value.minimumFreeSpaceGb, 2);
      expect(value.quality, 'standard');
    });

    test('keeps network preferences mutually exclusive', () {
      final value = DownloadPreferences.fromJson({
        'wifiOnly': true,
        'allowCellular': true,
      });
      expect(value.wifiOnly, isFalse);
      expect(value.allowCellular, isTrue);
    });

    test('normalizes unsupported storage and quality values', () {
      final value = DownloadPreferences.fromJson({
        'minimumFreeSpaceGb': 3,
        'quality': 'ultra-mega-lossless',
      });
      expect(value.minimumFreeSpaceGb, 2);
      expect(value.quality, 'standard');
    });

    test('accepts supported storage and lossless quality', () {
      final value = DownloadPreferences.fromJson({
        'minimumFreeSpaceGb': 10,
        'quality': 'lossless',
      });
      expect(value.minimumFreeSpaceGb, 10);
      expect(value.quality, 'lossless');
    });
  });
}
