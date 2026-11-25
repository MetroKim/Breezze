import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'playback_source_policy.dart';
import 'youtube_stream_probe.dart';

/// The media URL exists only in this request and in the native audio engine.
/// Never persist this record in Redis, PostgreSQL, Drift, or app preferences.
class DeviceYouTubeAudioCandidate {
  const DeviceYouTubeAudioCandidate({
    required this.url,
    required this.bitrate,
    required this.audioCodec,
    required this.container,
  });
  final Uri url;
  final int bitrate;
  final String audioCodec;
  final String container;
}

/// Validate the exact video identifier and a short-lived, direct, audio-only
/// Google media URL. Fails closed for arbitrary websites and expired links.
PlayableSource? selectDeviceYouTubeAudio(
  String trackId,
  Iterable<DeviceYouTubeAudioCandidate> candidates, {
  DateTime? nowUtc,
  Set<String> supportedContainers = const {'mp4'},
}) {
  if (!isYouTubeSongId(trackId)) return null;
  final now = (nowUtc ?? DateTime.now()).toUtc();
  final eligible = candidates.where((candidate) {
    final uri = candidate.url;
    final host = uri.host.toLowerCase();
    final expiresEpoch = int.tryParse(uri.queryParameters['expire'] ?? '');
    final container = candidate.container.toLowerCase();
    final codec = candidate.audioCodec.toLowerCase();
    final compatibleCodec = (container == 'mp4' &&
        (codec.startsWith('mp4a') || codec.contains('aac'))) ||
        (container == 'webm' &&
        (codec.contains('opus') || codec.contains('vorbis')));
    if (expiresEpoch == null ||
        expiresEpoch <= now.millisecondsSinceEpoch ~/ 1000 + 75 ||
        expiresEpoch > now.millisecondsSinceEpoch ~/ 1000 + 86400 ||
        candidate.bitrate < 16000 ||
        !supportedContainers.contains(container) ||
        !compatibleCodec ||
        uri.path != '/videoplayback' ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty || uri.hasFragment ||
        !(host == 'googlevideo.com' || host.endsWith('.googlevideo.com'))) {
      return false;
    }
    return true;
  }).toList()
    ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
  if (eligible.isEmpty) return null;
  final selected = eligible.first;
  final expiry = DateTime.fromMillisecondsSinceEpoch(
    int.parse(selected.url.queryParameters['expire']!) * 1000,
    isUtc: true,
  );
  return PlayableSource(
    trackId: trackId,
    streamUrl: selected.url.toString(),
    expiresAtUtc: expiry,
    codec: selected.audioCodec,
  );
}


typedef DeviceAudioProbe = Future<bool> Function(Uri url);

/// Emits stage codes only, never sensitive signed URLs or exception messages.
typedef DeviceAudioDiagnostic = void Function(String stage);

/// Find a compatible URL that actually responds to a media-range request.
/// A revoked/blocked candidate cannot consume the whole playback attempt:
/// try the next eligible encoding, up to a strict network budget. This is
/// an in-memory decision; signed URLs are never retained on disk.
Future<PlayableSource?> findReachableYouTubeAudio(
  String trackId,
  Iterable<DeviceYouTubeAudioCandidate> candidates, {
  required DeviceAudioProbe probe,
  DeviceAudioDiagnostic? diagnostic,
  DateTime? nowUtc,
  Set<String> supportedContainers = const {'mp4'},
  int maxProbeAttempts = 4,
}) async {
  if (!isYouTubeSongId(trackId) || maxProbeAttempts <= 0) {
    diagnostic?.call('INVALID_TRACK_OR_RETRY_BUDGET');
    return null;
  }
  final available = candidates.toList(growable: false);
  diagnostic?.call('AUDIO_CANDIDATES_${available.length}');
  final rejected = <String>{};
  for (var attempt = 0; attempt < maxProbeAttempts && attempt < 4; attempt++) {
    final source = selectDeviceYouTubeAudio(
      trackId,
      available.where((candidate) => !rejected.contains(candidate.url.toString())),
      nowUtc: nowUtc,
      supportedContainers: supportedContainers,
    );
    if (source == null) {
      diagnostic?.call('NO_COMPATIBLE_CANDIDATE');
      return null;
    }
    rejected.add(source.streamUrl);
    try {
      if (await probe(Uri.parse(source.streamUrl))) {
        diagnostic?.call('STREAM_PROBE_OK');
        return source;
      }
      diagnostic?.call('STREAM_PROBE_REJECTED');
    } catch (Object _) {
      diagnostic?.call('STREAM_PROBE_EXCEPTION');
      // A single failing CDN URL must not block the next audio format.
    }
  }
  diagnostic?.call('STREAM_PROBES_EXHAUSTED');
  return null;
}

/// Device-local resolver for Android/iOS/desktop native playback. It does not
/// proxy, persist, or download YouTube media. The native engine independently
/// streams the selected URL, and recovers by re-resolving after expiry.
class DeviceYouTubeAudioResolver {
  DeviceYouTubeAudioResolver({
    DeviceAudioProbe? probe,
    DeviceAudioDiagnostic? diagnostic,
  }) : _probe = probe ?? probeYouTubeAudioStream,
       _diagnostic = diagnostic;

  final DeviceAudioProbe _probe;
  final DeviceAudioDiagnostic? _diagnostic;

  Future<PlayableSource?> resolve(String trackId) async {
    if (kIsWeb || !isYouTubeSongId(trackId)) {
      _diagnostic?.call('NOT_NATIVE_YOUTUBE_TRACK');
      return null;
    }
    final videoId = trackId.substring('bz:youtube_music:'.length);
    final client = YoutubeExplode();
    try {
      _diagnostic?.call('MANIFEST_REQUESTED');
      final manifest = await client.videos.streams
          .getManifest(videoId)
          .timeout(const Duration(seconds: 12));
      _diagnostic?.call('MANIFEST_RECEIVED');
      // AVFoundation on iOS/macOS needs an MP4/AAC source. ExoPlayer and
      // media_kit can also decode WebM/Opus on supported Android/Linux builds.
      final platforms = switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.linux => const {'mp4', 'webm'},
        _ => const {'mp4'},
      };
      return await findReachableYouTubeAudio(
        trackId,
        manifest.audioOnly.map((stream) => DeviceYouTubeAudioCandidate(
          url: stream.url,
          bitrate: stream.bitrate.bitsPerSecond,
          audioCodec: stream.audioCodec,
          container: stream.container.name,
        )),
        supportedContainers: platforms,
        probe: _probe,
        diagnostic: _diagnostic,
      );
    } catch (Object error) {
      // Exception messages can include signed URLs. Expose TYPE only.
      _diagnostic?.call('SOURCE_EXCEPTION_${error.runtimeType}');
      // Caller retains the official visible video player fallback.
      return null;
    } finally {
      client.close();
    }
  }
}

final deviceYouTubeAudioResolverProvider =
    Provider<DeviceYouTubeAudioResolver>((ref) => DeviceYouTubeAudioResolver());
