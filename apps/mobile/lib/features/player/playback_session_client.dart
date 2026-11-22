import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/breezze_api.dart';

/// Transport seam for the global player's server-authorized playback session.
abstract interface class PlaybackSessionClient {
  Future<Map<String, dynamic>> heartbeat({
    required String sessionId,
    required String eventId,
    required int sequence,
  });

  Future<void> pause(String sessionId);
  Future<void> resume(String sessionId);
  Future<void> stop(String sessionId);
}

class ApiPlaybackSessionClient implements PlaybackSessionClient {
  ApiPlaybackSessionClient(this.api);

  final BreezzeApi api;

  @override
  Future<Map<String, dynamic>> heartbeat({
    required String sessionId,
    required String eventId,
    required int sequence,
  }) =>
      api.playbackHeartbeat(
        sessionId: sessionId,
        eventId: eventId,
        sequence: sequence,
      );

  @override
  Future<void> pause(String sessionId) => api.pausePlaybackSession(sessionId);

  @override
  Future<void> resume(String sessionId) => api.resumePlaybackSession(sessionId);

  @override
  Future<void> stop(String sessionId) => api.stopPlaybackSession(sessionId);
}

final playbackSessionClientProvider = Provider<PlaybackSessionClient>((ref) {
  throw UnimplementedError('Playback session client must be overridden');
});
