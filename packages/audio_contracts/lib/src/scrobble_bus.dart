/// Breezze scrobble bus — port of the proven Chordline KMP ScrobbleBus.
/// Enforces the 30-second minimum-play rule (§28/§30) shared by Last.fm
/// and ListenBrainz-style sinks.
library;

/// A scrobbling destination.
abstract interface class Scrobbler {
  String get id;

  /// Fire-and-forget submit; implement with retries as needed.
  Future<void> submit({
    required String trackId,
    required DateTime playedAtUtc,
  });
}

class ScrobbleBus {
  final List<Scrobbler> _scrobblers = [];
  final Map<String, _Pending> _pending = {};

  /// Both major scrobbling platforms require at least 30 s played.
  static const minPlayThreshold = Duration(seconds: 30);

  void register(Scrobbler scrobbler) => _scrobblers.add(scrobbler);

  /// Called when a track starts playing.
  void onPlay(String trackId, DateTime nowUtc) {
    _pending[trackId] = _Pending(trackId, nowUtc);
  }

  /// Called periodically while playing. Submits once the 30 s threshold
  /// has elapsed. Ticks are capped at 2 s each so pauses don't inflate.
  void onTick(String trackId, DateTime nowUtc) {
    final p = _pending[trackId];
    if (p == null) return;
    final last = p.lastTick;
    if (last != null) {
      final delta = nowUtc.difference(last);
      p.elapsed += delta > const Duration(seconds: 2)
          ? const Duration(seconds: 2)
          : delta;
    }
    p.lastTick = nowUtc;

    if (!p.submitted && p.elapsed >= minPlayThreshold) {
      p.submitted = true;
      for (final s in _scrobblers) {
        s.submit(trackId: trackId, playedAtUtc: nowUtc);
      }
    }
  }

  /// Called when a track stops or is skipped.
  void onStop(String trackId) => _pending.remove(trackId);
}

class _Pending {
  final String trackId;
  Duration elapsed = Duration.zero;
  DateTime? lastTick;
  bool submitted = false;

  _Pending(this.trackId, DateTime start) : lastTick = start;
}
