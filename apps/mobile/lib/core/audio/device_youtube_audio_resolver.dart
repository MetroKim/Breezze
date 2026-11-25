import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'playback_source_policy.dart';

/// The media URL exists only in this request and in the native audio engine.
/// Never persist this record in Redis, PostgreSQL, Drift, or app preferences.
class DeviceYouTubeAudioCandidate {
  const DeviceYouTubeAudioCandidate({
    required this.url,
    required this.bitrate,
    required this.audioCodec,
  });
  final Uri url;
  final int bitrate;
  final String audioCodec;
}

/// Validate the exact video identifier and a short-lived, direct, audio-only
/// Google media URL. Fails closed for arbitrary websites and expired links.
PlayableSource? selectDeviceYouTubeAudio(
  String trackId,
  Iterable<DeviceYouTubeAudioCandidate> candidates, {
  DateTime? nowUtc,
}) {
  if (!isYouTubeSongId(trackId)) return null;
  final now = (nowUtc ?? DateTime.now()).toUtc();
  final eligible = candidates.where((candidate) {
    final uri = candidate.url;
    final host = uri.host.toLowerCase();
    final expiresEpoch = int.tryParse(uri.queryParameters['expire'] ?? '');
    if (expiresEpoch == null || expiresEpoch < 1 ||
        candidate.bitrate < 16000 ||
        candidate.audioCodec.trim().isEmpty ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty || uri.hasFragment ||
        !(host == 'googlevideo.com' || host.endsWith('.googlevideo.com'))) {
      return false;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresEpoch * 1000, isUtc: true,
    );
    return expiresAt.isAfter(now.add(const Duration(seconds: 75)));
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

/// Device-local resolver for Android/iOS/desktop native playback. It does not
/// proxy, persist, or download YouTube media. The native engine independently
/// streams the selected URL, and recovers by re-resolving after expiry.
class DeviceYouTubeAudioResolver {
  Future<PlayableSource?> resolve(String trackId) async {
    if (kIsWeb || !isYouTubeSongId(trackId)) return null;
    final videoId = trackId.substring('bz:youtube_music:'.length);
    final client = YoutubeExplode();
    try {
      final manifest = await client.videos.streams
          .getManifest(videoId)
          .timeout(const Duration(seconds: 12));
      return selectDeviceYouTubeAudio(
        trackId,
        manifest.audioOnly.map((stream) => DeviceYouTubeAudioCandidate(
          url: stream.url,
          bitrate: stream.bitrate.bitsPerSecond,
          audioCodec: stream.audioCodec,
        )),
      );
    } catch (_) {
      // This source is not guaranteed available in every region or network.
      // Caller retains the visible official YouTube player fallback.
      return null;
    } finally {
      client.close();
    }
  }
}

final deviceYouTubeAudioResolverProvider =
    Provider<DeviceYouTubeAudioResolver>((ref) => DeviceYouTubeAudioResolver());
