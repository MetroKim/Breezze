/// Breezze V8.2 two-deck online audio transition renderer.
///
/// Both decks MUST already hold fully resolved, valid Breezze-native playback
/// grants. This component never obtains URLs, authorizes music, or stores a
/// provider stream. It drives equal-power overlapping audio; beat/key
/// analysis and pitch-preserving tempo DSP require separate native acceptance.
///
/// Only the global PlayerController may request this render operation.
/// It must keep both server playback sessions valid during the overlap.
library;

import 'dart:async';
import 'dart:math' as math;

import 'automix.dart';

abstract interface class OnlineAutomixDeck {
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> stop();
}

/// Source grant, account or audio focus changed during the transition.
class AutomixAuthorizationLost implements Exception {
  const AutomixAuthorizationLost();
}

/// Caller must supply a continually checked rights/session predicate.
/// A revoked or expired grant immediately stops both decks.
class OnlineAutomixRenderer {
  const OnlineAutomixRenderer();

  Future<void> render({
    required OnlineAutomixDeck outgoing,
    required OnlineAutomixDeck incoming,
    required MixTransition plan,
    required bool Function() bothSourcesAuthorized,
    int steps = 32,
    double masterVolume = 1,
    Future<void> Function(Duration)? delay,
  }) async {
    if (identical(outgoing, incoming)) {
      throw ArgumentError('Automix requires independent audio decks');
    }
    if (steps < 2 || steps > 120 ||
        plan.transitionMs < 250 || plan.transitionMs > 15000 ||
        !masterVolume.isFinite || masterVolume < 0 || masterVolume > 1) {
      throw ArgumentError('Automix transition outside supported bounds');
    }
    // A grant/session checker can fail when the backend or auth state changes.
    // Treat both a denied result and a thrown checker as lost permission.
    bool authorized() {
      try {
        return bothSourcesAuthorized();
      } catch (_) {
        return false;
      }
    }

    final wait = delay ?? (Duration d) => Future<void>.delayed(d);
    final transition = Duration(milliseconds: plan.transitionMs);
    try {
      if (!authorized()) throw const AutomixAuthorizationLost();
      await incoming.setVolume(0);
      if (!authorized()) throw const AutomixAuthorizationLost();
      await incoming.play();
      for (var i = 1; i <= steps; i++) {
        if (!authorized()) throw const AutomixAuthorizationLost();
        final elapsedBefore = transition.inMicroseconds * (i - 1) ~/ steps;
        final elapsedAfter = transition.inMicroseconds * i ~/ steps;
        await wait(Duration(microseconds: elapsedAfter - elapsedBefore));
        if (!authorized()) throw const AutomixAuthorizationLost();
        final theta = i / steps * math.pi / 2;
        await outgoing.setVolume(math.cos(theta) * masterVolume);
        await incoming.setVolume(math.sin(theta) * masterVolume);
      }
      if (!authorized()) throw const AutomixAuthorizationLost();
      // Authorization can change while the final volume operation awaits.
      if (!authorized()) throw const AutomixAuthorizationLost();
      // Commit the handoff only after the incoming deck has reached full
      // level and the grant has been rechecked. A decoder failure here must
      // leave the outgoing deck available for safe restoration.
      await incoming.setVolume(masterVolume);
      if (!authorized()) throw const AutomixAuthorizationLost();
      await outgoing.stop();
    } catch (_) {
      // play() may start audio and then throw before its Future completes.
      // Always attempt to silence the dedicated incoming deck, even if its
      // initial mute or play operation failed.
      try {
        await incoming.stop();
      } catch (_) {
        // Cleanup must not mask the original failure.
      }
      if (authorized()) {
        // Keep the original authorized recording audible on a transient
        // decoder error. A rights failure must mute BOTH instead.
        try {
          await outgoing.setVolume(masterVolume);
        } catch (_) {
          // Preserve the original transition error.
        }
      } else {
        try {
          await outgoing.stop();
        } catch (_) {
          // Preserve the original transition error.
        }
      }
      rethrow;
    }
  }
}
