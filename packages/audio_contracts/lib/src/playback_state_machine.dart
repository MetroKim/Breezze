/// Breezze playback state machine — spec §53.2.
///
/// IDLE → RESOLVING → LOADING → BUFFERING → PLAYING ↔ PAUSED
/// PLAYING → SEEKING → PLAYING
/// PLAYING → TRANSITIONING → PLAYING
/// PLAYING → COMPLETED
/// ANY ACTIVE → INTERRUPTED / FAILED / OFFLINE
library;

/// Complete playback states (§9.3).
enum PlaybackState {
  idle,
  resolving,
  loading,
  buffering,
  playing,
  paused,
  seeking,
  transitioning,
  ended,
  failed,
  interrupted,
  offline,
}

/// Events that drive the state machine. Every transition must define
/// timeout, cancellation and user-visible feedback (§53.2).
sealed class PlaybackEvent {}

class StartRequested extends PlaybackEvent {
  final String trackId;
  StartRequested(this.trackId);
}

class SourceResolved extends PlaybackEvent {
  final String trackId;
  final String streamUrl;
  SourceResolved(this.trackId, this.streamUrl);
}

class SourceResolutionFailed extends PlaybackEvent {
  final String code;
  SourceResolutionFailed(this.code);
}

class MediaReady extends PlaybackEvent {}

class BufferingStarted extends PlaybackEvent {}

class PlayPressed extends PlaybackEvent {}

class PausePressed extends PlaybackEvent {}

class SeekRequested extends PlaybackEvent {
  final Duration position;
  SeekRequested(this.position);
}

class SeekCompleted extends PlaybackEvent {}

class TrackTransitioned extends PlaybackEvent {
  final String newTrackId;
  TrackTransitioned(this.newTrackId);
}

class TrackCompleted extends PlaybackEvent {}

class InterruptionDetected extends PlaybackEvent {}

class InterruptionEnded extends PlaybackEvent {}

class ConnectionLost extends PlaybackEvent {}

class ConnectionRestored extends PlaybackEvent {}

/// Transitions are centralized and testable — no screen may mutate state
/// directly (§53.1: one global PlayerController owns playback state).
class PlaybackStateMachine {
  PlaybackState _state = PlaybackState.idle;
  final void Function(PlaybackState previous, PlaybackState next)? onTransition;

  PlaybackStateMachine({this.onTransition});

  PlaybackState get state => _state;

  /// Applies an event, returning the new state.
  PlaybackState dispatch(PlaybackEvent event) {
    final before = _state;
    _state = _reduce(_state, event);
    if (before != _state) onTransition?.call(before, _state);
    return _state;
  }

  PlaybackState _reduce(PlaybackState s, PlaybackEvent e) {
    switch (s) {
      case PlaybackState.idle:
        if (e is StartRequested) return PlaybackState.resolving;
        if (e is TrackTransitioned) return PlaybackState.resolving;
        return s;

      case PlaybackState.resolving:
        if (e is SourceResolved) return PlaybackState.loading;
        if (e is SourceResolutionFailed) return PlaybackState.failed;
        if (e is ConnectionLost) return PlaybackState.offline;
        return s;

      case PlaybackState.loading:
        if (e is MediaReady) return PlaybackState.buffering;
        if (e is SourceResolutionFailed) return PlaybackState.failed;
        if (e is ConnectionLost) return PlaybackState.offline;
        return s;

      case PlaybackState.buffering:
        if (e is PlayPressed) return PlaybackState.playing;
        if (e is ConnectionLost) return PlaybackState.offline;
        return s;

      case PlaybackState.playing:
        if (e is PausePressed) return PlaybackState.paused;
        if (e is SeekRequested) return PlaybackState.seeking;
        if (e is TrackTransitioned) return PlaybackState.transitioning;
        if (e is TrackCompleted) return PlaybackState.ended;
        if (e is InterruptionDetected) return PlaybackState.interrupted;
        if (e is ConnectionLost) return PlaybackState.offline;
        return s;

      case PlaybackState.paused:
        if (e is PlayPressed) return PlaybackState.playing;
        if (e is TrackTransitioned) return PlaybackState.transitioning;
        return s;

      case PlaybackState.seeking:
        if (e is SeekCompleted) return PlaybackState.playing;
        if (e is ConnectionLost) return PlaybackState.offline;
        return s;

      case PlaybackState.transitioning:
        if (e is MediaReady) return PlaybackState.buffering;
        if (e is ConnectionLost) return PlaybackState.offline;
        return s;

      case PlaybackState.ended:
        if (e is StartRequested) return PlaybackState.resolving;
        if (e is TrackTransitioned) return PlaybackState.transitioning;
        return s;

      case PlaybackState.failed:
        if (e is StartRequested) return PlaybackState.resolving;
        return s;

      case PlaybackState.interrupted:
        if (e is InterruptionEnded) return PlaybackState.paused;
        return s;

      case PlaybackState.offline:
        if (e is ConnectionRestored) return PlaybackState.paused;
        if (e is StartRequested) return PlaybackState.resolving;
        return s;
    }
  }
}
