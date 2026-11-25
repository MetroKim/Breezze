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
