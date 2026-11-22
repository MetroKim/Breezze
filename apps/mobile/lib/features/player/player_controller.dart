import 'dart:async';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/recent_store.dart';

/// Global PlayerController — spec §51.3, §53.1.
///
/// THE one application-wide playback authority. All screens dispatch
/// commands to it; a screen must never instantiate its own player for
/// catalog playback. Navigation never resets audio (§26.3).
class PlayerController extends Notifier<PlayerState> {
  late final PlaybackStateMachine _machine = PlaybackStateMachine(
    onTransition: (prev, next) {
      state = state.copyWith(playbackState: next);
    },
  );

  late final QueueManager _queue = QueueManager(
    onQueueChanged: () {
      state = state.copyWith(queueVersion: state.queueVersion + 1);
    },
  );

  late final ScrobbleBus _scrobbles = ScrobbleBus();
  final RecentStore _recent = RecentStore();

  AudioEngineAdapter? _engine;
  PlayableSource? _activeSource;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlaybackState>? _engineStateSub;
  int _requestGeneration = 0;
  String? _autoAdvancedTrackId;
  Future<void> _engineOperations = Future<void>.value();

  /// Track info remembered for the current queue, keyed by track id.
  final Map<String, TrackInfo> _trackInfos = {};

  @override
  PlayerState build() {
    ref.onDispose(() {
      _requestGeneration++;
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
      _positionSub?.cancel();
      _engineStateSub?.cancel();
      _engine = null;
      _activeSource = null;
    });
    return PlayerState.initial();
  }

  QueueManager get queue => _queue;

  void attachEngine(AudioEngineAdapter engine) {
    _requestGeneration++;
    _positionSub?.cancel();
    _engineStateSub?.cancel();
    _engine = engine;

    _positionSub = engine.positionStream.listen((pos) {
      if (!identical(_engine, engine)) return;
      state = state.copyWith(position: pos, duration: engine.duration);
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null &&
          state.playbackState == PlaybackState.playing) {
        _scrobbles.onTick(currentTrackId, DateTime.now().toUtc());
      }
    });
    _engineStateSub = engine.engineStateStream.listen((engineState) {
      if (!identical(_engine, engine)) return;

      // Ignore events emitted by the previous media item while the new
      // source is being resolved/prepared.
      if (state.playbackState == PlaybackState.idle ||
          state.playbackState == PlaybackState.resolving ||
          state.playbackState == PlaybackState.loading ||
          state.playbackState == PlaybackState.transitioning) {
        return;
      }
      // Keep the state machine authoritative when the OS pauses audio
      // because of a call, another exclusive session, or route removal.
      if (engineState == PlaybackState.interrupted &&
          _machine.state == PlaybackState.playing) {
        _machine.dispatch(InterruptionDetected());
        return;
      }
      if (engineState == PlaybackState.paused &&
          _machine.state == PlaybackState.interrupted) {
        _machine.dispatch(InterruptionEnded());
        return;
      }
      if (engineState == PlaybackState.paused &&
          _machine.state == PlaybackState.playing) {
        _machine.dispatch(PausePressed());
        return;
      }
      state = state.copyWith(playbackState: engineState);
      if (engineState == PlaybackState.ended ||
          engineState == PlaybackState.failed) {
        final currentTrackId = state.currentTrack?.id;
        if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
        // just_audio reports completion on the engine stream. Advance the
        // single app-wide queue here so playback continues without requiring
        // the user to tap Next. The guard prevents duplicate completed events
        // from advancing more than once for the same item.
        if (engineState == PlaybackState.ended &&
            currentTrackId != null &&
            _autoAdvancedTrackId != currentTrackId) {
          _autoAdvancedTrackId = currentTrackId;
          unawaited(next());
        }
      }
    });
  }

  void detachEngine() {
    final currentTrackId = state.currentTrack?.id;
    if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
    _requestGeneration++;
    _positionSub?.cancel();
    _engineStateSub?.cancel();
    _positionSub = null;
    _engineStateSub = null;
    _engine = null;
    _activeSource = null;
  }

  bool _isMetadataOnlyProviderTrack(String id) =>
      id.startsWith('bzv:') ||
      (id.startsWith('bz:') && !id.startsWith('bz:audius:'));

  // ----------------------------------------------------------------
  // Commands
  // ----------------------------------------------------------------

  Future<void> playTrack({
    required String trackId,
    String? title,
    String? artist,
    String? artworkUrl,
    String? localFilePath,
    Duration duration = Duration.zero,
    List<TrackInfo> queue = const [],
    int startIndex = 0,
    String origin = 'manual',
    String sourceContext = 'Breezze',
  }) async {
    // YouTube Music search results are catalogue metadata, not native
    // playback grants. Never put them into Breezze's native queue.
    if ((_isMetadataOnlyProviderTrack(trackId) && localFilePath == null) ||
        queue.any((item) => _isMetadataOnlyProviderTrack(item.id) && item.localFilePath == null)) {
      return;
    }
    if (queue.isNotEmpty) {
      final entries = [
        for (var i = 0; i < queue.length; i++)
          QueueEntry(
            entryId: 'qe-$trackId-$i-${DateTime.now().microsecondsSinceEpoch}',
            trackId: queue[i].id,
            origin: origin,
            sourceContext: sourceContext,
            insertedAtMs: DateTime.now().millisecondsSinceEpoch,
            trackVersion: 'v1',
          ),
      ];
      _queue.replaceWith(entries, startIndex: startIndex);
      for (final item in queue) {
        _trackInfos[item.id] = item;
      }
    } else {
      final entry = QueueEntry(
        entryId: 'qe-${DateTime.now().microsecondsSinceEpoch}',
        trackId: trackId,
        origin: origin,
        sourceContext: sourceContext,
        insertedAtMs: DateTime.now().millisecondsSinceEpoch,
        trackVersion: 'v1',
      );
      _queue.replaceWith([entry]);
    }

    final info = queue.isEmpty
        ? TrackInfo(
            id: trackId,
            title: title,
            artist: artist,
            artworkUrl: artworkUrl,
            localFilePath: localFilePath,
            duration: duration,
          )
        : queue[startIndex.clamp(0, queue.length - 1)];

    await _resolveAndPlay(info);
  }

  /// Stops playback and clears the current queue. Used on explicit user stop
  /// and account sign-out so one user's media cannot continue into another
  /// account session.
  Future<void> stop() async {
    final requestId = ++_requestGeneration;
    final engine = _engine;
    final currentTrackId = state.currentTrack?.id;
    if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
    _queue.clear(keepCurrent: false);
    _trackInfos.clear();
    _activeSource = null;
    _machine.dispatch(StopRequested(requestId: requestId));
    state = state.copyWith(
      clearCurrentTrack: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    if (engine == null) return;
    try {
      await _serializeEngineOperation(() => engine.stop());
    } catch (_) {
      // The logical player is already idle; native stop is best-effort.
    }
  }

  Future<void> pause() async {
    final engine = _engine;
    if (engine == null || state.playbackState != PlaybackState.playing) return;
    _machine.dispatch(PausePressed());
    try {
      await _serializeEngineOperation(() => engine.pause());
    } catch (_) {
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
      _machine.dispatch(SourceResolutionFailed('PAUSE_FAILED', requestId: _machine.activeRequestId));
    }
  }

  Future<void> resume() async {
    final engine = _engine;
    if (engine == null || state.playbackState != PlaybackState.paused) return;
    final activeSource = _activeSource;
    final currentTrack = state.currentTrack;
    if (activeSource != null && activeSource.isExpired && currentTrack != null) {
      // Provider grants are short-lived. Resolve a fresh grant instead of
      // attempting to resume a stale URL after a long pause/background.
      await _resolveAndPlay(currentTrack, initialPosition: state.position);
      return;
    }
    _machine.dispatch(PlayPressed());
    try {
      await _serializeEngineOperation(() async {
        unawaited(engine.play().catchError(
          (Object error, StackTrace stackTrace) {
            final currentTrackId = state.currentTrack?.id;
            if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
            _machine.dispatch(SourceResolutionFailed(
              'RESUME_FAILED',
              requestId: _machine.activeRequestId,
            ));
          },
        ));
      });
    } catch (_) {
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
      _machine.dispatch(SourceResolutionFailed(
        'RESUME_FAILED',
        requestId: _machine.activeRequestId,
      ));
    }
  }

  Future<void> togglePlayPause() async {
    if (state.playbackState == PlaybackState.playing) {
      await pause();
    } else if (state.playbackState == PlaybackState.paused) {
      await resume();
    }
  }

  Future<void> seekTo(Duration position) async {
    final engine = _engine;
    final wasPlaying = state.playbackState == PlaybackState.playing;
    final wasPaused = state.playbackState == PlaybackState.paused;
    if (engine == null || (!wasPlaying && !wasPaused)) return;

    if (wasPlaying) _machine.dispatch(SeekRequested(position));
    try {
      await _serializeEngineOperation(() => engine.seek(position));
      state = state.copyWith(position: position);
      if (wasPlaying) _machine.dispatch(SeekCompleted());
    } catch (_) {
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
      _machine.dispatch(SourceResolutionFailed(
        'SEEK_FAILED',
        requestId: _machine.activeRequestId,
      ));
    }
  }

  Future<void> next() async {
    final entry = _queue.advance();
    if (entry == null) return;
    final info = _trackInfoFor(entry.trackId) ?? TrackInfo(id: entry.trackId);
    await _resolveAndPlay(info);
  }

  Future<void> previous() async {
    final entry = _queue.previous();
    if (entry == null) return;
    final info = _trackInfoFor(entry.trackId) ?? TrackInfo(id: entry.trackId);
    await _resolveAndPlay(info);
  }

  /// Inserts a track directly after the current item.
  void playNext(TrackInfo track, {
    String origin = 'manual',
    String sourceContext = 'Queue',
  }) {
    if (_isMetadataOnlyProviderTrack(track.id) && track.localFilePath == null) return;
    _trackInfos[track.id] = track;
    if (state.currentTrack == null) {
      unawaited(playTrack(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.artworkUrl,
        duration: track.duration,
        origin: origin,
        sourceContext: sourceContext,
      ));
      return;
    }
    _queue.playNext(QueueEntry(
      entryId: 'qe-${DateTime.now().microsecondsSinceEpoch}',
      trackId: track.id,
      origin: origin,
      sourceContext: sourceContext,
      insertedAtMs: DateTime.now().millisecondsSinceEpoch,
      trackVersion: 'v1',
    ));
  }

  /// Appends a track to the end of the current queue.
  void playLast(TrackInfo track, {
    String origin = 'manual',
    String sourceContext = 'Queue',
  }) {
    if (_isMetadataOnlyProviderTrack(track.id) && track.localFilePath == null) return;
    _trackInfos[track.id] = track;
    if (state.currentTrack == null) {
      unawaited(playTrack(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.artworkUrl,
        duration: track.duration,
        origin: origin,
        sourceContext: sourceContext,
      ));
      return;
    }
    _queue.playLast(QueueEntry(
      entryId: 'qe-${DateTime.now().microsecondsSinceEpoch}',
      trackId: track.id,
      origin: origin,
      sourceContext: sourceContext,
      insertedAtMs: DateTime.now().millisecondsSinceEpoch,
      trackVersion: 'v1',
    ));
  }

  /// Register a Last.fm/ListenBrainz-compatible scrobbling destination.
  void registerScrobbler(Scrobbler scrobbler) {
    _scrobbles.register(scrobbler);
  }

  void toggleShuffle() => _queue.toggleShuffle();
  void cycleRepeat() => _queue.cycleRepeat();

  TrackInfo? _trackInfoFor(String trackId) => _trackInfos[trackId];

  /// Read-only metadata lookup for queue and playlist surfaces.
  TrackInfo? trackInfoFor(String trackId) => _trackInfoFor(trackId);

  bool _isCurrentRequest(int requestId) =>
      requestId == _requestGeneration && _engine != null;

  /// Serializes native engine mutations. Resolution remains concurrent, but
  /// prepare/play operations execute in order so an older prepare cannot
  /// finish after and overwrite a newer selected track.
  Future<void> _serializeEngineOperation(
      Future<void> Function() operation) {
    final result = _engineOperations.then((_) => operation());
    _engineOperations = result.catchError((_) {});
    return result;
  }

  Future<void> _resolveAndPlay(
    TrackInfo info, {
    Duration initialPosition = Duration.zero,
  }) async {
    // Defensive check for restored or stale queue entries created before the
    // metadata-only provider capability was enforced.
    if (_isMetadataOnlyProviderTrack(info.id) && info.localFilePath == null) return;
    final previousTrackId = state.currentTrack?.id;
    if (previousTrackId != null && previousTrackId != info.id) {
      _scrobbles.onStop(previousTrackId);
    }
    final requestId = ++_requestGeneration;
    _autoAdvancedTrackId = null;
    _trackInfos[info.id] = info;
    state = state.copyWith(
      currentTrack: info,
      position: initialPosition,
      duration: info.duration,
    );
    _machine.dispatch(StartRequested(info.id, requestId: requestId));

    try {
      final source = info.localFilePath != null
          ? PlayableSource(
              trackId: info.id,
              streamUrl: info.localFilePath!,
              expiresAtUtc: DateTime.utc(9999),
              isLocal: true,
            )
          : await ref.read(playbackResolverProvider).resolve(info);
      if (!_isCurrentRequest(requestId)) return;

      if (source == null) {
        _activeSource = null;
        _machine.dispatch(SourceResolutionFailed(
          'NOT_AVAILABLE',
          requestId: requestId,
        ));
        return;
      }

      _activeSource = source;
      _machine.dispatch(SourceResolved(
        info.id,
        source.streamUrl,
        requestId: requestId,
      ));
      if (_machine.state != PlaybackState.loading) return;

      final engine = _engine;
      if (engine == null) {
        _machine.dispatch(SourceResolutionFailed(
          'AUDIO_ENGINE_UNAVAILABLE',
          requestId: requestId,
        ));
        return;
      }

      await _serializeEngineOperation(() async {
        if (!_isCurrentRequest(requestId) || !identical(_engine, engine)) {
          return;
        }

        await engine.prepare(source);
        if (!_isCurrentRequest(requestId) || !identical(_engine, engine)) {
          return;
        }
        if (initialPosition > Duration.zero) {
          await engine.seek(initialPosition);
          if (!_isCurrentRequest(requestId) || !identical(_engine, engine)) {
            return;
          }
        }

        _machine.dispatch(MediaReady(requestId: requestId));
        if (_machine.state != PlaybackState.buffering) return;
        _machine.dispatch(PlayPressed());
        if (_machine.state != PlaybackState.playing) return;

        // just_audio's play Future completes when playback stops, not when
        // playback first starts. Do not await the whole song here.
        unawaited(engine.play().catchError(
          (Object error, StackTrace stackTrace) {
            if (_isCurrentRequest(requestId)) {
              _scrobbles.onStop(info.id);
              _machine.dispatch(SourceResolutionFailed(
                'PLAYBACK_FAILED',
                requestId: requestId,
              ));
            }
          },
        ));
      });

      if (!_isCurrentRequest(requestId) ||
          _machine.state != PlaybackState.playing) {
        return;
      }

      if (info.title != null) {
        unawaited(_recent
            .record(
              info.id,
              info.title!,
              info.artist ?? '',
              info.artworkUrl,
              info.duration,
            )
            .catchError((_) {}));
      }
      unawaited(
        ref.read(playHistoryReporterProvider)(info).catchError((_) {}),
      );
      _scrobbles.onPlay(info.id, DateTime.now().toUtc());
    } catch (_) {
      if (_isCurrentRequest(requestId)) {
        _machine.dispatch(SourceResolutionFailed(
          'PLAYBACK_SETUP_FAILED',
          requestId: requestId,
        ));
      }
    }
  }
}

/// Display info for a track — what Now Playing renders.
class TrackInfo {
  final String id;
  final String? title;
  final String? artist;
  final String? artworkUrl;
  final String? localFilePath;
  final Duration duration;

  const TrackInfo({
    required this.id,
    this.title,
    this.artist,
    this.artworkUrl,
    this.localFilePath,
    this.duration = Duration.zero,
  });
}

/// The backend playback resolver contract — platform-agnostic.
abstract interface class PlaybackResolver {
  Future<PlayableSource?> resolve(TrackInfo track);
}

/// Provider for the resolver; overridden in bootstrap with the real
/// implementation.
final playbackResolverProvider = Provider<PlaybackResolver>((ref) {
  throw UnimplementedError('Overridden in bootstrap');
});

/// Immutable player state exposed to the UI.
class PlayerState {
  final PlaybackState playbackState;
  final Duration position;
  final Duration duration;
  final TrackInfo? currentTrack;

  /// Bumped on queue mutations; UI listens to this to rebuild queue views.
  final int queueVersion;

  const PlayerState({
    required this.playbackState,
    required this.position,
    required this.duration,
    required this.currentTrack,
    required this.queueVersion,
  });

  factory PlayerState.initial() => const PlayerState(
        playbackState: PlaybackState.idle,
        position: Duration.zero,
        duration: Duration.zero,
        currentTrack: null,
        queueVersion: 0,
      );

  PlayerState copyWith({
    PlaybackState? playbackState,
    Duration? position,
    Duration? duration,
    TrackInfo? currentTrack,
    bool clearCurrentTrack = false,
    int? queueVersion,
  }) {
    return PlayerState(
      playbackState: playbackState ?? this.playbackState,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentTrack: clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
      queueVersion: queueVersion ?? this.queueVersion,
    );
  }
}

/// Reports successfully started plays to the backend for listening history
/// and artist analytics. The default is a no-op for isolated player tests.
typedef PlayHistoryReporter = Future<void> Function(TrackInfo track);

final playHistoryReporterProvider = Provider<PlayHistoryReporter>(
  (ref) => (track) async {},
);

/// The single global provider — one instance app-wide (§53.1).
final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
