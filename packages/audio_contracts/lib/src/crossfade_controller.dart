/// Breezze crossfade controller — port of the proven Chordline KMP
/// CrossfadeController, per spec §9.7 (crossfade as its own system,
/// separate from AutoMix) and §61.
library;

import 'dart:async';

/// Emitted exactly [CrossfadeController.crossfadeMs] before a track's end
/// so the engine can blend outgoing and incoming streams (§9.7).
class CrossfadeEvent {
  final String trackId;
  final Duration remaining;
  CrossfadeEvent(this.trackId, this.remaining);
}

class CrossfadeController {
  /// Transition duration, 0–12 s per spec §9.7.
  final Duration crossfadeMs;

  final _events = StreamController<CrossfadeEvent>.broadcast();
  Stream<CrossfadeEvent> get events => _events.stream;

  Timer? _timer;

  CrossfadeController({this.crossfadeMs = Duration.zero});

  bool get active => crossfadeMs > Duration.zero;

  /// Called when a track starts, with its duration.
  void start(String trackId, Duration duration) {
    _timer?.cancel();
    if (!active || duration <= Duration.zero) return;

    final delay = duration - crossfadeMs;
    if (delay < Duration.zero) return;

    String? triggeredFor;
    _timer = Timer(delay, () {
      if (triggeredFor == null) {
        triggeredFor = trackId;
        _events.add(CrossfadeEvent(trackId, crossfadeMs));
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _events.close();
  }
}
