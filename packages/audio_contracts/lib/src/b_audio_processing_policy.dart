/// Eligibility rules for optional Breezze audio enhancements.
///
/// This is a pure-Dart contract, not a DSP implementation. Each native
/// adapter must prove model, device, and rights readiness before enabling
/// processing. Never infer fidelity from the output sample rate alone.
library;

import 'audio_quality.dart';

enum BAudioEffect { upscale, spatial, autoMix }

enum BAudioGateStatus {
  disabled,
  rightsDenied,
  deviceUnsupported,
  modelUnavailable,
  ready,
}

class BAudioGateDecision {
  const BAudioGateDecision({
    required this.effect,
    required this.status,
  });

  final BAudioEffect effect;
  final BAudioGateStatus status;

  bool get canStart => status == BAudioGateStatus.ready;
}

/// Produces a deterministic decision. No network, disk, or audio side effects.
///
/// A model must be verified (integrity and compatibility) before [modelReady]
/// is true. A caller cannot use this gate to bypass playback authorization:
/// [transformationPermitted] comes from the rights layer, not client settings.
class BAudioProcessingPolicy {
  const BAudioProcessingPolicy();

  BAudioGateDecision evaluate({
    required BAudioEffect effect,
    required bool enabled,
    required bool transformationPermitted,
    required bool deviceSupported,
    bool requiresModel = false,
    bool modelReady = false,
  }) {
    final status = !enabled
        ? BAudioGateStatus.disabled
        : !transformationPermitted
            ? BAudioGateStatus.rightsDenied
            : !deviceSupported
                ? BAudioGateStatus.deviceUnsupported
                : requiresModel && !modelReady
                    ? BAudioGateStatus.modelUnavailable
                    : BAudioGateStatus.ready;

    return BAudioGateDecision(effect: effect, status: status);
  }

  /// AI-generated frequencies do not turn a lossy original into lossless.
  /// The actual source quality stays authoritative in the UI and telemetry.
  String presentationLabel({
    required AudioQualityTier sourceTier,
    required bool enhancementActive,
  }) {
    return enhancementActive
        ? 'Enhanced ${sourceTier.label}'
        : sourceTier.label;
  }
}
