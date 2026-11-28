import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bounded live-stream recovery. Playback rights and recording identity do
/// not change on retry. Three failures max, then surface the actual failure.
const defaultPlaybackRecoveryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 3),
  Duration(seconds: 7),
];

/// Override with short delays only in deterministic QA tests.
final playbackRecoveryDelaysProvider =
    Provider<List<Duration>>((ref) => defaultPlaybackRecoveryDelays);

Duration? nextStreamRecoveryDelay({
  required PlayableSource? source,
  required PlaybackState state,
  required int attempt,
  List<Duration> delays = defaultPlaybackRecoveryDelays,
}) {
  if (source == null ||
      source.isLocal ||
      state != PlaybackState.failed ||
      attempt < 0 ||
      attempt >= delays.length) return null;

  final delay = delays[attempt];
  // Guard against invalid injected policy values, preventing timer storms.
  if (delay.isNegative) return null;
  return delay;
}

/// Quality is reduced only after a failed authorized remote stream. This
/// does not select a different recording, bypass a license, or convert a
/// metadata provider's URL into playable media. The server still enforces
/// the requested ceiling, territories, grant expiry and available encodings.
///
/// A first retry moves down one rendition; subsequent retries move lower
/// until AAC_128. Fresh user-initiated playback resets the retry budget.
String recoveryQualityForRetry(String requested, int retryCount) {
  const order = <String>['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES'];
  if (retryCount <= 0) return requested;
  final index = order.indexOf(requested);
  if (index < 0) return requested; // Let the server reject invalid requests.
  final target = index - retryCount;
  return order[target < 0 ? 0 : target];
}
