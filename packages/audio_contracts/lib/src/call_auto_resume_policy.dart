/// A deterministic, side-effect-free policy for phone/exclusive-audio focus.
/// It never authorizes playback: the global PlayerController must re-check
/// its server playback session and grant before resuming.
class CallAutoResumePolicy {
  bool _interruptionActive = false;
  bool _armed = false;

  /// Arm only when an actual call-like interruption paused playing audio.
  /// Duck-only interruptions do not qualify for automatic restart.
  void begin({required bool wasPlaying, required bool callLike}) {
    if (_interruptionActive) return;
    _interruptionActive = true;
    _armed = wasPlaying && callLike;
  }

  /// Explicit pause/stop/skip, account switching, or route removal cancels it.
  void cancel() {
    _armed = false;
  }

  /// Consume at most one request when the same interruption ends.
  bool end() {
    final resume = _interruptionActive && _armed;
    _interruptionActive = false;
    _armed = false;
    return resume;
  }
}
