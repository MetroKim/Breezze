import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_recovery_policy.dart';

void main() {
  final remote = PlayableSource(
    trackId: 'licensed-track',
    streamUrl: 'https://cdn.example/audio',
    expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 3)),
  );
  final local = PlayableSource(
    trackId: 'local-track',
    streamUrl: '/app/audio.m4a',
    expiresAtUtc: DateTime.utc(9999),
    isLocal: true,
  );

  test('tries a fresh remote grant at bounded increasing intervals', () {
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.failed, attempt: 0,
    ), const Duration(seconds: 1));
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.failed, attempt: 1,
    ), const Duration(seconds: 3));
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.failed, attempt: 2,
    ), const Duration(seconds: 7));
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.failed, attempt: 3,
    ), isNull);
  });

  test('does not retry local files, missing or ungranted remote sources', () {
    expect(nextStreamRecoveryDelay(
      source: null, state: PlaybackState.failed, attempt: 0,
    ), isNull);
    expect(nextStreamRecoveryDelay(
      source: local, state: PlaybackState.failed, attempt: 0,
    ), isNull);
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.paused, attempt: 0,
    ), isNull);
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.failed, attempt: -1,
    ), isNull);
    expect(nextStreamRecoveryDelay(
      source: remote, state: PlaybackState.failed, attempt: 0,
      delays: [const Duration(seconds: -1)],
    ), isNull);
  });
}
