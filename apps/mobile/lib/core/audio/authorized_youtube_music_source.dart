import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'playback_source_policy.dart';
import 'remote_audio_grant.dart';

/// Accepts a full-length server-approved, signed recording, never raw
/// YouTube Music metadata, a watch URL, or an unlicensed audio candidate.
PlayableSource? authorizedYouTubeMusicPlayback(
  String trackId, Map<String, dynamic> session, {DateTime? nowUtc}
) {
  if (!isYouTubeSongId(trackId)) return null;
  final sessionId = session['id'];
  final playback = session['playback'];
  if (sessionId is! String || sessionId.isEmpty || playback is! Map) return null;
  final url = playback['streamUrl'];
  final rawExpires = playback['expiresAt'];
  if (url is! String || rawExpires is! String) return null;
  final expiry = DateTime.tryParse(rawExpires);
  if (expiry == null || !isUsableRemoteAudioGrant(url, expiry, nowUtc: nowUtc)) {
    return null;
  }
  final codec = playback['codec'];
  return PlayableSource(
    trackId: trackId, streamUrl: url, sessionId: sessionId,
    expiresAtUtc: expiry.toUtc(), codec: codec is String ? codec : null,
  );
}
