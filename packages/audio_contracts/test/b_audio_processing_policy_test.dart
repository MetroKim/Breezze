import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = BAudioProcessingPolicy();

  test('processing is disabled by default', () {
    final result = policy.evaluate(
      effect: BAudioEffect.upscale,
      enabled: false,
      transformationPermitted: true,
      deviceSupported: true,
      requiresModel: true,
      modelReady: true,
    );
    expect(result.status, BAudioGateStatus.disabled);
    expect(result.canStart, isFalse);
  });

  test('rights denial overrides installed models', () {
    final result = policy.evaluate(
      effect: BAudioEffect.spatial,
      enabled: true,
      transformationPermitted: false,
      deviceSupported: true,
      requiresModel: true,
      modelReady: true,
    );
    expect(result.status, BAudioGateStatus.rightsDenied);
  });

  test('unsupported device cannot start effect', () {
    final result = policy.evaluate(
      effect: BAudioEffect.autoMix,
      enabled: true,
      transformationPermitted: true,
      deviceSupported: false,
    );
    expect(result.status, BAudioGateStatus.deviceUnsupported);
  });

  test('a missing model prevents execution', () {
    final result = policy.evaluate(
      effect: BAudioEffect.upscale,
      enabled: true,
      transformationPermitted: true,
      deviceSupported: true,
      requiresModel: true,
    );
    expect(result.status, BAudioGateStatus.modelUnavailable);
  });

  test('ready requires all specified gates to pass', () {
    final result = policy.evaluate(
      effect: BAudioEffect.spatial,
      enabled: true,
      transformationPermitted: true,
      deviceSupported: true,
      requiresModel: true,
      modelReady: true,
    );
    expect(result.canStart, isTrue);
    expect(result.effect, BAudioEffect.spatial);
  });

  test('upscaled lossy audio is never labeled lossless', () {
    expect(
      policy.presentationLabel(
        sourceTier: AudioQualityTier.high,
        enhancementActive: true,
      ),
      'Enhanced AAC · 256 kbps',
    );
    expect(
      policy.presentationLabel(
        sourceTier: AudioQualityTier.high,
        enhancementActive: false,
      ),
      'AAC · 256 kbps',
    );
  });
}
