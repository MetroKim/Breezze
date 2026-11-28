import 'dart:async';
import 'dart:math';

import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/recent_store.dart';
import '../../core/auth/auth_session.dart';
import '../../core/audio/playback_source_policy.dart';
import '../../core/audio/playback_recovery_policy.dart';
import '../../core/database/database_providers.dart';
import '../../core/database/playback_heartbeat_outbox_dao.dart';
import 'playback_session_client.dart';

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
  StreamSubscription<bool>? _callResumeSub;
  Future<void>? _interruptionServerPause;
  int _requestGeneration = 0;
  String? _autoAdvancedTrackId;
  Timer? _streamRecoveryTimer;
  int _streamRecoveryAttempts = 0;
  int _streamRecoveryToken = 0;
  DateTime? _lastConfirmedPlaybackAt;

  /// Local/authorized remote sources only. Never retries a denied grant or
  /// substitutes a preview, another recording, or an unofficial provider.
  void _cancelStreamRecovery({bool resetBudget = true}) {
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _streamRecoveryToken++;
    if (resetBudget) {
      _streamRecoveryAttempts = 0;
      _lastConfirmedPlaybackAt = null;
    }
  }

  void _scheduleStreamRecovery(int requestId) {
    if (_streamRecoveryTimer != null ||
        requestId != _requestGeneration ||
        state.playbackState != PlaybackState.failed) return;
    final selected = state.currentTrack;
    final source = _activeSource;
    final engine = _engine;
    if (selected == null || source == null || source.trackId != selected.id ||
        engine == null) return;

    // A healthy playback period replenishes the bounded retry budget.
    // Rapid failures consume it rather than looping indefinitely.
    final lastStartedAt = _lastConfirmedPlaybackAt;
    if (lastStartedAt != null &&
        DateTime.now().difference(lastStartedAt) >
            const Duration(minutes: 1)) {
      _streamRecoveryAttempts = 0;
    }
    final delay = nextStreamRecoveryDelay(
      source: source,
      state: state.playbackState,
      attempt: _streamRecoveryAttempts,
      delays: ref.read(playbackRecoveryDelaysProvider),
    );
    if (delay == null) return;

    _streamRecoveryAttempts++;
    final token = ++_streamRecoveryToken;
    final position = state.position;
    _streamRecoveryTimer = Timer(delay, () {
      _streamRecoveryTimer = null;
      if (token != _streamRecoveryToken ||
          requestId != _requestGeneration ||
          !identical(_engine, engine) ||
          state.playbackState != PlaybackState.failed ||
          state.currentTrack?.id != selected.id) return;
      // New resolver call obtains a fresh URL and a new authorized server
      // session. Never replay an expired bearer URL.
      unawaited(_resolveAndPlay(selected, initialPosition: position));
    });
  }
  /// Preserve the user's maximum quality for a fresh play. On a repeated
  /// stream failure only, request a smaller licensed rendition for this
  /// exact track. Every attempt re-resolves a fresh server-authorized URL.
  String streamingQualityFor(String trackId, String preferredQuality) {
    if (state.currentTrack?.id != trackId || _streamRecoveryAttempts <= 0) {
      return preferredQuality;
    }
    return recoveryQualityForRetry(preferredQuality, _streamRecoveryAttempts);
  }

  Future<void> _engineOperations = Future<void>.value();

  String? _playbackSessionId;
  PlaybackSessionClient? _activeSessionClient;
  Timer? _heartbeatTimer;
  int _heartbeatSequence = 1;
  String? _pendingHeartbeatEventId;
  bool _heartbeatInFlight = false;
  bool _heartbeatRecoveryInFlight = false;

  PlaybackHeartbeatOutboxDao get _heartbeatOutbox =>
      PlaybackHeartbeatOutboxDao(ref.read(breezzeDatabaseProvider));

  PlaybackSessionClient get _sessionClient =>
      ref.read(playbackSessionClientProvider);

  String _newEventId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    if (_playbackSessionId == null) return;
    _heartbeatTimer = Timer.periodic(
      ref.read(playbackHeartbeatIntervalProvider),
      (_) {
        if (state.playbackState == PlaybackState.playing) {
          unawaited(_sendPlaybackHeartbeat());
        }
      },
    );
  }

  void _pauseHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _sendPlaybackHeartbeat() async {
    final sessionId = _playbackSessionId;
    if (sessionId == null ||
        _heartbeatInFlight ||
        state.playbackState != PlaybackState.playing) {
      return;
    }
    _heartbeatInFlight = true;
    final eventId = _pendingHeartbeatEventId ??= _newEventId();
    try {
      final client = _activeSessionClient;
      if (client == null) return;
      final auth = ref.read(authSessionProvider);
      if (auth is AuthSignedIn) {
        // Commit the exact idempotency key and sequence before sending. If
        // the process dies after the server commits but before the response
        // arrives, startup recovery can safely replay the same event.
        await _heartbeatOutbox.save(
          ownerId: auth.userId,
          sessionId: sessionId,
          eventId: eventId,
          sequence: _heartbeatSequence,
        );
      }
      final result = await client.heartbeat(
        sessionId: sessionId,
        eventId: eventId,
        sequence: _heartbeatSequence,
      );
      if (result['accepted'] == true && _playbackSessionId == sessionId) {
        if (auth is AuthSignedIn) {
          await _heartbeatOutbox.remove(sessionId: sessionId, eventId: eventId);
        }
        _pendingHeartbeatEventId = null;
        _heartbeatSequence++;
      }
    } catch (_) {
      // Keep the same event ID and sequence; the next timer tick retries it.
    } finally {
      _heartbeatInFlight = false;
    }
  }

  Future<void> _closePlaybackSession() async {
    _pauseHeartbeatTimer();
    final sessionId = _playbackSessionId;
    final client = _activeSessionClient;
    _playbackSessionId = null;
    _activeSessionClient = null;
    _pendingHeartbeatEventId = null;
    _heartbeatSequence = 1;
    if (sessionId == null) return;
    if (client == null) return;
    try {
      await client.stop(sessionId);
      final auth = ref.read(authSessionProvider);
      if (auth is AuthSignedIn) {
        await _heartbeatOutbox.removeSession(
          ownerId: auth.userId,
          sessionId: sessionId,
        );
      }
    } catch (_) {
      // Keep any pending event durable; startup recovery will replay it and
      // close the session. The server TTL is the final safety net.
    }
  }

  Future<void> _recoverPendingHeartbeats(String ownerId) async {
    if (_heartbeatRecoveryInFlight) return;
    _heartbeatRecoveryInFlight = true;
    try {
      final client = _sessionClient;
      final entries = await _heartbeatOutbox.pending(ownerId: ownerId);
      // A session can have multiple queued heartbeat events. Replay every
      // event in sequence before stopping that session; stopping after the
      // first row would invalidate later events and lose their credit.
      final sessions = <String, List<PlaybackHeartbeatOutboxEntry>>{};
      for (final entry in entries) {
        sessions.putIfAbsent(entry.sessionId, () => []).add(entry);
      }
      for (final session in sessions.entries) {
        final auth = ref.read(authSessionProvider);
        if (auth is! AuthSignedIn || auth.userId != ownerId) return;
        final pendingEvents = session.value
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
        var replayFailed = false;
        for (final entry in pendingEvents) {
          final currentAuth = ref.read(authSessionProvider);
          if (currentAuth is! AuthSignedIn || currentAuth.userId != ownerId) {
            return;
          }
          try {
            // Replay the original key/sequence. The server treats an already
            // committed heartbeat as an acknowledged duplicate.
            final result = await client.heartbeat(
              sessionId: entry.sessionId,
              eventId: entry.eventId,
              sequence: entry.sequence,
            );
            if (result['accepted'] == true) {
              await _heartbeatOutbox.remove(
                sessionId: entry.sessionId,
                eventId: entry.eventId,
              );
            } else {
              replayFailed = true;
            }
          } catch (_) {
            replayFailed = true;
          }
        }
        // Close only after every queued event for this session was replayed.
        // If any event could not be acknowledged, retain its row and let the
        // server TTL expire rather than deleting uncredited retry evidence.
        if (!replayFailed) {
          try {
            await client.stop(session.key);
            await _heartbeatOutbox.removeSession(
              ownerId: ownerId,
              sessionId: session.key,
            );
          } catch (_) {
            // Retain the row for a later authenticated recovery attempt.
          }
        }
      }
    } catch (_) {
      // Local database/network failures must not block normal playback.
    } finally {
      _heartbeatRecoveryInFlight = false;
      final current = ref.read(authSessionProvider);
      if (current is AuthSignedIn && current.userId != ownerId) {
        unawaited(_recoverPendingHeartbeats(current.userId));
      }
    }
  }

  void _adoptPlaybackSession(PlayableSource source) {
    _playbackSessionId = source.sessionId;
    _activeSessionClient = source.sessionId == null ? null : _sessionClient;
    _heartbeatSequence = 1;
    _pendingHeartbeatEventId = null;
  }

  Future<void> _pauseServerSession() async {
    _pauseHeartbeatTimer();
    final sessionId = _playbackSessionId;
    final client = _activeSessionClient;
    if (sessionId == null || client == null) return;
    try {
      await client.pause(sessionId);
    } catch (_) {
      // Do not keep crediting an active server session after an unconfirmed
      // pause. A later resume obtains a fresh authorized session.
      await _closePlaybackSession();
    }
  }

  /// Track info remembered for the current queue, keyed by track id.
  final Map<String, TrackInfo> _trackInfos = {};

  @override
  PlayerState build() {
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      if (next is AuthSignedIn) {
        unawaited(_recoverPendingHeartbeats(next.userId));
      }
    });
    final auth = ref.read(authSessionProvider);
    if (auth is AuthSignedIn) {
      unawaited(_recoverPendingHeartbeats(auth.userId));
    }
    ref.onDispose(() {
      _cancelStreamRecovery();
      _requestGeneration++;
      unawaited(_closePlaybackSession());
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
      _positionSub?.cancel();
      _engineStateSub?.cancel();
      _callResumeSub?.cancel();
      _engine = null;
      _activeSource = null;
    });
    return PlayerState.initial();
  }

  QueueManager get queue => _queue;

  void attachEngine(AudioEngineAdapter engine) {
    _cancelStreamRecovery();
    _requestGeneration++;
    _positionSub?.cancel();
    _engineStateSub?.cancel();
    _callResumeSub?.cancel();
    _engine = engine;
    if (engine is CallInterruptionResumeSource) {
      _callResumeSub = (engine as CallInterruptionResumeSource)
          .callResumeRequests.listen((shouldResume) {
        if (!shouldResume || !identical(_engine, engine)) return;
        final generation = _requestGeneration;
        final trackId = state.currentTrack?.id;
        if (trackId == null) return;
        // OS events are asynchronous. Give interrupted -> paused a turn to
        // settle, then use the controller's normal rights/session-aware resume.
        unawaited(Future<void>.delayed(Duration.zero).then((_) async {
          if (generation != _requestGeneration ||
              !identical(_engine, engine) ||
              state.currentTrack?.id != trackId ||
              state.playbackState != PlaybackState.paused) return;
          await resume();
        }));
      });
    }

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
          // A cancelled preparation/restored queue has no attached source.
          // Late callbacks from the previous native item must not flip it
          // into playing, failed, or ended after the listener pressed Pause.
          (_activeSource == null &&
              state.playbackState == PlaybackState.paused) ||
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
        // A short call can finish before the pause RPC is acknowledged.
        // Serialize the pause against resume so the resumed session never
        // receives a late "pause" after the media has restarted.
        final pauseRequest = _pauseServerSession();
        _interruptionServerPause = pauseRequest;
        unawaited(pauseRequest.whenComplete(() {
          if (identical(_interruptionServerPause, pauseRequest)) {
            _interruptionServerPause = null;
          }
        }));
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
        unawaited(_pauseServerSession());
        return;
      }
      if (engineState == PlaybackState.failed) {
        _machine.dispatch(SourceResolutionFailed(
          'STREAM_FAILED',
          requestId: _machine.activeRequestId,
        ));
        final currentTrackId = state.currentTrack?.id;
        if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
        unawaited(_closePlaybackSession());
        _scheduleStreamRecovery(_requestGeneration);
        return;
      }
      state = state.copyWith(playbackState: engineState);
      if (engineState == PlaybackState.playing &&
          _lastConfirmedPlaybackAt == null) {
        _lastConfirmedPlaybackAt = DateTime.now();
      }
      if (engineState == PlaybackState.ended) {
        final currentTrackId = state.currentTrack?.id;
        if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
        // just_audio reports completion on the engine stream. Advance the
        // single app-wide queue here so playback continues without requiring
        // the user to tap Next. The guard prevents duplicate completed events
        // from advancing more than once for the same item.
        unawaited(_closePlaybackSession());
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
    _cancelStreamRecovery();
    final currentTrackId = state.currentTrack?.id;
    if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
    unawaited(_closePlaybackSession());
    _requestGeneration++;
    _positionSub?.cancel();
    _engineStateSub?.cancel();
    _positionSub = null;
    _engineStateSub = null;
    _engine = null;
    _activeSource = null;
  }


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
    if ((isMetadataOnlyTrackId(trackId) && localFilePath == null) ||
        queue.any((item) => isMetadataOnlyTrackId(item.id) && item.localFilePath == null)) {
      return;
    }
    _cancelStreamRecovery();
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
    if (_engine is CallInterruptionResumeSource) {
      (_engine! as CallInterruptionResumeSource).cancelPendingCallResume();
    }
    _cancelStreamRecovery();
    final requestId = ++_requestGeneration;
    final engine = _engine;
    final currentTrackId = state.currentTrack?.id;
    if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
    await _closePlaybackSession();
    _queue.reset();
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
    _cancelStreamRecovery();
    final engine = _engine;
    if (engine == null) return;
    if (state.playbackState == PlaybackState.interrupted) {
      // Explicit user/OS pause while the phone owns focus forbids auto resume.
      if (engine is CallInterruptionResumeSource) {
        (engine as CallInterruptionResumeSource).cancelPendingCallResume();
      }
      return;
    }
    // A user can press Pause before the resolver or native prepare finishes.
    // Cancel that request rather than allowing its future completion to
    // autoplay a song after the listener asked for silence.
    if (state.playbackState == PlaybackState.resolving ||
        state.playbackState == PlaybackState.loading ||
        state.playbackState == PlaybackState.buffering) {
      final track = state.currentTrack;
      if (track == null) return;
      final cancelledRequestId = ++_requestGeneration;
      _activeSource = null;
      _machine.dispatch(StopRequested(requestId: cancelledRequestId));
      _machine.dispatch(RestorePaused(track.id));
      _pauseHeartbeatTimer();
      await _closePlaybackSession();
      try {
        // Native prepare and stop are serialized. An immediate Resume starts
        // a new request, so its source cannot be stopped by this old command.
        await _serializeEngineOperation(() async {
          if (cancelledRequestId == _requestGeneration &&
              identical(_engine, engine)) {
            await engine.stop();
          }
        });
      } catch (_) {
        // The cancelled generation is already unable to begin playback.
      }
      return;
    }
    if (state.playbackState != PlaybackState.playing) return;
    _machine.dispatch(PausePressed());
    _pauseHeartbeatTimer();
    try {
      await _serializeEngineOperation(() => engine.pause());
      await _pauseServerSession();
    } catch (_) {
      final currentTrackId = state.currentTrack?.id;
      if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
      await _closePlaybackSession();
      _machine.dispatch(SourceResolutionFailed('PAUSE_FAILED', requestId: _machine.activeRequestId));
    }
  }

  Future<void> resume() async {
    _cancelStreamRecovery();
    final engine = _engine;
    if (engine == null || state.playbackState != PlaybackState.paused) return;
    final generation = _requestGeneration;
    final pendingPause = _interruptionServerPause;
    if (pendingPause != null) {
      await pendingPause;
      // Stop/track switch/user pause while waiting revokes this resume.
      if (generation != _requestGeneration ||
          !identical(_engine, engine) ||
          state.playbackState != PlaybackState.paused) return;
    }
    final activeSource = _activeSource;
    final currentTrack = state.currentTrack;
    if (activeSource != null && activeSource.isExpired && currentTrack != null) {
      // Provider grants are short-lived. Resolve a fresh grant instead of
      // attempting to resume a stale URL after a long pause/background.
      await _resolveAndPlay(currentTrack, initialPosition: state.position);
      return;
    }
    if (activeSource == null && currentTrack != null) {
      // A restored queue contains metadata only, never an old signed URL.
      await _resolveAndPlay(currentTrack, initialPosition: state.position);
      return;
    }
    final sessionId = _playbackSessionId;
    if (activeSource?.sessionId != null &&
        sessionId == null &&
        currentTrack != null) {
      await _resolveAndPlay(currentTrack, initialPosition: state.position);
      return;
    }
    if (sessionId != null) {
      try {
        await (_activeSessionClient ?? _sessionClient).resume(sessionId);
      } catch (_) {
        // A server playback session can expire before its media URL (e.g.
        // the server's two-hour authorization lease). A failed resume must
        // never keep using the old source. Resolve a fresh grant while
        // preserving the requested position and existing queue.
        await _closePlaybackSession();
        if (currentTrack != null) {
          await _resolveAndPlay(currentTrack, initialPosition: state.position);
        }
        return;
      }
    }
    _machine.dispatch(PlayPressed());
    try {
      await _serializeEngineOperation(() async {
        unawaited(engine.play().catchError(
          (Object error, StackTrace stackTrace) {
            final currentTrackId = state.currentTrack?.id;
            if (currentTrackId != null) _scrobbles.onStop(currentTrackId);
            unawaited(_closePlaybackSession());
            _machine.dispatch(SourceResolutionFailed(
              'RESUME_FAILED',
              requestId: _machine.activeRequestId,
            ));
          },
        ));
      });
      if (sessionId != null && state.playbackState == PlaybackState.playing) {
        _startHeartbeatTimer();
      }
    } catch (_) {
      await _closePlaybackSession();
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
    } else if (state.playbackState == PlaybackState.interrupted) {
      // A tap during a call is a manual decision: never auto resume.
      await pause();
    } else if (state.playbackState == PlaybackState.failed ||
        state.playbackState == PlaybackState.ended) {
      final track = state.currentTrack;
      if (track != null) await _resolveAndPlay(track);
    }
  }

  Future<void> seekTo(Duration position) async {
    final engine = _engine;
    final wasPlaying = state.playbackState == PlaybackState.playing;
    final wasPaused = state.playbackState == PlaybackState.paused;
    if (engine == null || (!wasPlaying && !wasPaused)) return;

    // Restored or cancelled playback has no prepared native source yet.
    // Seeking the stopped engine would fail and corrupt the paused queue;
    // store the requested offset for the next fresh authorized resolve.
    if (wasPaused && _activeSource == null) {
      final maximum = state.duration;
      final bounded = position.isNegative
          ? Duration.zero
          : (maximum > Duration.zero && position > maximum
              ? maximum
              : position);
      state = state.copyWith(position: bounded);
      return;
    }

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
    _cancelStreamRecovery();
    final entry = _queue.advance();
    if (entry == null) return;
    final info = _trackInfoFor(entry.trackId) ?? TrackInfo(id: entry.trackId);
    await _resolveAndPlay(info);
  }

  Future<void> previous() async {
    _cancelStreamRecovery();
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
    if (isMetadataOnlyTrackId(track.id) && track.localFilePath == null) return;
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
    if (isMetadataOnlyTrackId(track.id) && track.localFilePath == null) return;
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

  /// A versioned account-local queue snapshot containing metadata only.
  /// Never persist source URLs, grants, server-session IDs or local paths.
  Map<String, dynamic>? exportQueueSnapshot() {
    final current = state.currentTrack;
    final selected = _queue.current;
    final entries = _queue.entries;
    if (current == null || selected == null || entries.length > 200 ||
        entries.any((e) => e.trackId.startsWith('device:') ||
            !canQueueTrackId(e.trackId) ||
            _trackInfos[e.trackId]?.localFilePath != null)) {
      return null;
    }
    return {
      'v': 1,
      'selected': selected.entryId,
      'repeat': _queue.repeatMode.name,
      'shuffle': _queue.shuffle,
      'shuffledOrder': _queue.shuffledOrder,
      'positionMs': state.position.inMilliseconds,
      'entries': [
        for (final e in entries)
          {
            'id': e.entryId,
            'track': e.trackId,
            'origin': e.origin,
            'context': e.sourceContext,
            'collection': e.sourceCollectionId,
            'insertedAtMs': e.insertedAtMs,
            'version': e.trackVersion,
          }
      ],
      'tracks': [
        for (final id in entries.map((e) => e.trackId).toSet())
          {
            'id': id,
            'title': _trackInfos[id]?.title,
            'artist': _trackInfos[id]?.artist,
            'durationMs': _trackInfos[id]?.duration.inMilliseconds ?? 0,
          },
      ],
    };
  }

  /// Restores paused metadata, not actual audio. A tap on Play must obtain
  /// a new server grant from the regular resolver before preparing the engine.
  bool restoreQueueSnapshot(Map<String, dynamic> snapshot) {
    if (state.currentTrack != null || _queue.current != null ||
        state.playbackState != PlaybackState.idle ||
        snapshot['v'] != 1) {
      return false;
    }
    try {
      final rows = snapshot['entries'];
      final infos = snapshot['tracks'];
      if (rows is! List || rows.isEmpty || rows.length > 200 ||
          infos is! List || infos.length > 200) return false;
      final entries = <QueueEntry>[];
      for (final row in rows) {
        if (row is! Map) return false;
        final id = row['id'];
        final track = row['track'];
        if (id is! String || id.isEmpty || id.length > 256 ||
            track is! String || track.isEmpty || track.length > 256 ||
            track.startsWith('device:') || !canQueueTrackId(track)) {
          return false;
        }
        entries.add(QueueEntry(
          entryId: id,
          trackId: track,
          origin: (row['origin'] as String?) ?? 'restored',
          sourceContext: (row['context'] as String?) ?? 'Restored queue',
          sourceCollectionId: row['collection'] as String?,
          insertedAtMs: (row['insertedAtMs'] as num?)?.toInt() ?? 0,
          trackVersion: (row['version'] as String?) ?? 'v1',
        ));
      }
      final tracks = <String, TrackInfo>{};
      for (final row in infos) {
        if (row is! Map || row['id'] is! String) return false;
        final id = row['id'] as String;
        final title = row['title'];
        final artist = row['artist'];
        if (title is String && title.length > 512 ||
            artist is String && artist.length > 512 ||
            !canQueueTrackId(id)) return false;
        final durationMs = (row['durationMs'] as num?)?.toInt() ?? 0;
        if (durationMs < 0 || durationMs > 24 * 60 * 60 * 1000) return false;
        tracks[id] = TrackInfo(
          id: id,
          title: title is String ? title : null,
          artist: artist is String ? artist : null,
          duration: Duration(milliseconds: durationMs),
        );
      }
      final selectedId = snapshot['selected'];
      final currentEntry = entries.where((e) => e.entryId == selectedId).firstOrNull;
      if (currentEntry == null || !tracks.containsKey(currentEntry.trackId) ||
          entries.any((e) => !tracks.containsKey(e.trackId))) return false;
      final mode = RepeatMode.values.where(
          (m) => m.name == snapshot['repeat']).firstOrNull ?? RepeatMode.off;
      final orderRaw = snapshot['shuffledOrder'];
      final order = orderRaw is List && orderRaw.every((x) => x is String)
          ? orderRaw.cast<String>() : <String>[];
      final ms = (snapshot['positionMs'] as num?)?.toInt() ?? 0;
      if (ms < 0 || ms > 24 * 60 * 60 * 1000) return false;

      _queue.restore(entries, currentEntryId: currentEntry.entryId,
          repeat: mode, shuffleEnabled: snapshot['shuffle'] == true,
          shuffledOrder: order);
      _trackInfos
        ..clear()
        ..addAll(tracks);
      _activeSource = null;
      _requestGeneration++;
      _machine.dispatch(RestorePaused(currentEntry.trackId));
      state = state.copyWith(
        currentTrack: tracks[currentEntry.trackId],
        position: Duration(milliseconds: ms),
        duration: tracks[currentEntry.trackId]!.duration,
      );
      return true;
    } catch (_) {
      // Corrupted snapshots fail closed, without activating any media URL.
      return false;
    }
  }

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
    if (isMetadataOnlyTrackId(info.id) && info.localFilePath == null) return;
    if (_engine is CallInterruptionResumeSource) {
      (_engine! as CallInterruptionResumeSource).cancelPendingCallResume();
    }
    final requestId = ++_requestGeneration;
    final previousTrackId = state.currentTrack?.id;
    if (previousTrackId != null && previousTrackId != info.id) {
      _scrobbles.onStop(previousTrackId);
    }
    _autoAdvancedTrackId = null;
    _trackInfos[info.id] = info;
    state = state.copyWith(
      currentTrack: info,
      position: initialPosition,
      duration: info.duration,
    );
    _machine.dispatch(StartRequested(info.id, requestId: requestId));

    try {
      // Detach the old session immediately. Source lookup and stopping the
      // previous item can proceed together. The engine queue orders prepare
      // after pause, including when two selections arrive back to back.
      unawaited(_closePlaybackSession());
      _activeSource = null;
      if (previousTrackId != null) {
        unawaited(_serializeEngineOperation(() async {
          if (_isCurrentRequest(requestId)) await _engine?.pause();
        }).catchError((Object _) {}));
      }
      final source = info.localFilePath != null
          ? PlayableSource(
              trackId: info.id,
              streamUrl: info.localFilePath!,
              expiresAtUtc: DateTime.utc(9999),
              isLocal: true,
            )
          : await ref.read(playbackResolverProvider).resolve(info);
      if (!_isCurrentRequest(requestId)) {
        if (source?.sessionId != null) {
          try { await _sessionClient.stop(source!.sessionId!); } catch (_) {}
        }
        return;
      }

      if (source == null) {
        if (!_isCurrentRequest(requestId)) return;
        _activeSource = null;
        _machine.dispatch(SourceResolutionFailed(
          'NOT_AVAILABLE',
          requestId: requestId,
        ));
        return;
      }

      _activeSource = source;
      _adoptPlaybackSession(source);
      _machine.dispatch(SourceResolved(
        info.id,
        source.streamUrl,
        requestId: requestId,
      ));
      if (_machine.state != PlaybackState.loading) {
        await _closePlaybackSession();
        return;
      }

      final engine = _engine;
      if (engine == null) {
        await _closePlaybackSession();
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
              unawaited(_closePlaybackSession());
              _machine.dispatch(SourceResolutionFailed(
                'PLAYBACK_FAILED',
                requestId: requestId,
              ));
              _scheduleStreamRecovery(requestId);
            }
          },
        ));
      });

      if (!_isCurrentRequest(requestId)) return;
      if (_machine.state != PlaybackState.playing) {
        await _closePlaybackSession();
        return;
      }
      _startHeartbeatTimer();

      if (info.title != null && !info.id.startsWith('device:')) {
        final auth = ref.read(authSessionProvider);
        final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
        unawaited(_recent
            .record(
              ownerId,
              info.id,
              info.title!,
              info.artist ?? '',
              info.artworkUrl,
              info.duration,
            )
            .catchError((_) {}));
      }
      // Session stop is now the authoritative qualified-play event.
      // Keep the legacy reporter only for local/offline media, which has no
      // server playback session.
      if (source.sessionId == null && !info.id.startsWith('device:') &&
          !isDeezerPreview(info.id) && !isYouTubeSongId(info.id)) {
        unawaited(
          ref.read(playHistoryReporterProvider)(info).catchError((_) {}),
        );
      }
      _scrobbles.onPlay(info.id, DateTime.now().toUtc());
    } catch (_) {
      if (_isCurrentRequest(requestId)) {
        await _closePlaybackSession();
        if (!_isCurrentRequest(requestId)) return;
        _machine.dispatch(SourceResolutionFailed(
          'PLAYBACK_SETUP_FAILED',
          requestId: requestId,
        ));
        _scheduleStreamRecovery(requestId);
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
