/// Breezze AutoMix — Dart port of the proven Chordline KMP Automix core.
///
/// DJ-style transitions with beat-matching and tempo-stretching (§9.7).
/// AutoMix is a separate system from crossfade: crossfade is the fixed
/// blend window, AutoMix decides HOW and WHEN compatible tracks blend.
library;

import 'dart:math' as math;

/// Per-track analysis driving the mix decision.
class TrackAnalysis {
  final int bpm;

  /// Perceived energy, 0.0–1.0.
  final double energy;

  const TrackAnalysis({required this.bpm, required this.energy});
}

/// The transition plan for an outgoing -> incoming pair.
class MixTransition {
  final bool beatMatched;

  /// Tempo factor to apply to the incoming track; 1.0 = unchanged.
  final double tempoFactor;

  /// Length of the overlap in ms.
  final int transitionMs;

  /// True when the incoming track must be double/half-time folded.
  final bool doubleTimeFold;

  const MixTransition({
    required this.beatMatched,
    required this.tempoFactor,
    required this.transitionMs,
    required this.doubleTimeFold,
  });
}

class Automix {
  /// Base transition length in ms, scaled by pair energy.
  final int baseTransitionMs;

  /// BPM match tolerance; ±10 % like the parent project.
  static const matchTolerance = 0.10;

  const Automix({this.baseTransitionMs = 4000});

  /// Plans a DJ-style transition. BPMs within ±10 % (after folding one
  /// track by 2x or 0.5x) are beat-matched, and the incoming tempo is
  /// stretched toward the outgoing tempo.
  MixTransition plan(TrackAnalysis outgoing, TrackAnalysis incoming) {
    const folds = [1.0, 2.0, 0.5];
    var bestFold = 1.0;
    var bestRatio = double.infinity;

    for (final fold in folds) {
      if (outgoing.bpm == 0) break;
      final ratio = (incoming.bpm * fold) / outgoing.bpm;
      if ((1.0 - ratio).abs() < (1.0 - bestRatio).abs()) {
        bestRatio = ratio;
        bestFold = fold;
      }
    }

    final matched = (1.0 - bestRatio).abs() <= matchTolerance;
    final energy = math.max(outgoing.energy, incoming.energy).clamp(0.0, 1.0);
    final transitionMs = (baseTransitionMs * (0.5 + energy)).round();

    return MixTransition(
      beatMatched: matched,
      tempoFactor: matched ? 1.0 / bestRatio : 1.0,
      transitionMs: transitionMs,
      doubleTimeFold: matched && bestFold != 1.0,
    );
  }
}
