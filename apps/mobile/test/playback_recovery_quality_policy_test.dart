import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_recovery_policy.dart';

void main() {
  group('authorized streaming quality recovery', () {
    test('fresh playback preserves the user quality preference', () {
      for (final quality in const ['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES']) {
        expect(recoveryQualityForRetry(quality, 0), quality);
        expect(recoveryQualityForRetry(quality, -1), quality);
      }
    });

    test('failures progressively lower bandwidth without upgrading', () {
      expect(recoveryQualityForRetry('HI_RES', 1), 'LOSSLESS');
      expect(recoveryQualityForRetry('HI_RES', 2), 'AAC_256');
      expect(recoveryQualityForRetry('HI_RES', 3), 'AAC_128');
      expect(recoveryQualityForRetry('LOSSLESS', 1), 'AAC_256');
      expect(recoveryQualityForRetry('LOSSLESS', 2), 'AAC_128');
      expect(recoveryQualityForRetry('AAC_256', 1), 'AAC_128');
    });

    test('lowest quality stays bounded even after repeated failures', () {
      expect(recoveryQualityForRetry('AAC_128', 1), 'AAC_128');
      expect(recoveryQualityForRetry('AAC_256', 3), 'AAC_128');
      expect(recoveryQualityForRetry('HI_RES', 500), 'AAC_128');
    });

    test('invalid quality does not silently become an unauthorized tier', () {
      expect(recoveryQualityForRetry('UNSUPPORTED', 2), 'UNSUPPORTED');
    });
  });
}
