import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global PlayerController — spec §51.3, §53.1.
///
/// THE one application-wide playback authority. All screens dispatch
/// commands to it; a screen must never instantiate its own player for
/// catalog playback. Navigation never resets audio (§26.3).
class PlayerController extends Notifier<PlayerState> {
  late final PlaybackStateMachine _machine = PlaybackStateMachine(
    onTransition: (prev, next) {
      final s = state;
      state = s.copyWith(playbackState: next);
    },
  );

  late final QueueManager _queue = QueueManager(
    onQueueChanged: () {
      final s = state;
      state = s.copyWith(queueVersion: s.queueVersion + 1);
    },
  );

  late final ScrobbleBus _scrobbles = ScrobbleBus();

  AudioEngineAdapter? _engine;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlaybackState>? _engineStateSub;

  @override
  PlayerState build() => PlayerState.initial();

  QueueManager get queue => _queue;

  void attachEngine(AudioEngineAdapter engine) {
    _engine = engine;
    _positionSub?.cancel();
    _engineStateSub?.cancel();
    _positionSub = engine.positionStream.listen((pos) {
      final s = state;
      // Isolate high-frequency updates (§51.6): screens select only what
      // they need from this state.
      state = s.copyWith(position: pos);
    });
    _engineStateSub = engine.engineStateStream.listen((st) {
      final s = state;
      state = s.copyWith(playbackState: st);
    });
  }

  void detachEngine() {
    _positionSub?.cancel();
    _engineStateSub?.cancel();
    _engine = null;
  }

  // ----------------------------------------------------------------
  // Commands (every command goes through the state machine, §53.2)
  // ----------------------------------------------------------------

  Future<void> playTrack({
    required String trackId,
    String origin = 'manual',
    String sourceContext = 'Breezze',
    String? sourceCollectionId,
  }) async {
    final entry = QueueEntry(
      entryId: 'qe-${DateTime.now().microsecondsSinceEpoch}',
      trackId: trackId,
      origin: origin,
      sourceContext: sourceContext,
      sourceCollectionId: sourceCollectionId,
      insertedAtMs: DateTime.now().millisecondsSinceEpoch,
      trackVersion: 'v1',
    );
    _queue.replaceWith([entry]);
    await _resolveAndPrepare(entry);
    _machine.dispatch(PlayPressed());
    await _engine?.play();
    _scrobbles.onPlay(trackId, DateTime.now().toUtc());
  }

  Future<void> togglePlayPause() async {
    if (state.playbackState == PlaybackState.playing) {
      _machine.dispatch(PausePressed());
      await _engine?.pause();
    } else {
      _machine.dispatch(PlayPressed());
      await _engine?.play();
    }
  }

  Future<void> seekTo(Duration position) async {
    _machine.dispatch(SeekRequested(position));
    await _engine?.seek(position);
    _machine.dispatch(SeekCompleted());
  }

  Future<void> next() async {
    final entry = _queue.advance();
    if (entry == null) return;
    await _resolveAndPrepare(entry);
    _machine.dispatch(TrackTransitioned(entry.trackId));
    await _engine?.play();
  }

  Future<void> previous() async {
    final entry = _queue.previous();
    if (entry == null) return;
    await _resolveAndPrepare(entry);
    await _engine?.play();
  }

  void toggleShuffle() => _queue.toggleShuffle();

  void cycleRepeat() => _queue.cycleRepeat();

  Future<void> _resolveAndPrepare(QueueEntry entry) async {
    _machine.dispatch(StartRequested(entry.trackId));
    // The PlaybackResolver (backend) supplies the authorized source; the
    // client never constructs stream URLs itself (§29.9, §52.4).
    final source =
        await ref.read(playbackResolverProvider).resolve(entry.trackId);
    if (source == null) {
      _machine.dispatch(SourceResolutionFailed('NOT_AVAILABLE'));
      return;
    }
    _machine.dispatch(SourceResolved(entry.trackId, source.streamUrl));
    await _engine?.prepare(source);
    _machine.dispatch(MediaReady());
  }
}

/// The backend playback resolver contract — platform-agnostic.
abstract interface class PlaybackResolver {
  /// Returns an authorized, short-lived [PlayableSource] or null when the
  /// track is unavailable in the user's territory/entitlement (§29.9).
  Future<PlayableSource?> resolve(String trackId);
}

/// Provider for the resolver; overridden in bootstrap with the real
/// API-backed implementation.
final playbackResolverProvider = Provider<PlaybackResolver>((ref) {
  throw UnimplementedError('Overridden in bootstrap');
});

/// Immutable player state exposed to the UI.
class PlayerState {
  final PlaybackState playbackState;
  final Duration position;
  final Duration duration;

  /// Bumped on queue mutations; UI listens to this to rebuild queue views.
  final int queueVersion;

  const PlayerState({
    required this.playbackState,
    required this.position,
    required this.duration,
    required this.queueVersion,
  });

  factory PlayerState.initial() => const PlayerState(
        playbackState: PlaybackState.idle,
        position: Duration.zero,
        duration: Duration.zero,
        queueVersion: 0,
      );

  PlayerState copyWith({
    PlaybackState? playbackState,
    Duration? position,
    Duration? duration,
    int? queueVersion,
  }) {
    return PlayerState(
      playbackState: playbackState ?? this.playbackState,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queueVersion: queueVersion ?? this.queueVersion,
    );
  }
}

/// The single global provider — one instance app-wide (§53.1).
final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
