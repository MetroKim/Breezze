import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active music resumes once when a phone call ends', () {
    final policy = CallAutoResumePolicy();
    policy.begin(wasPlaying: true, callLike: true);
    expect(policy.end(), isTrue);
    expect(policy.end(), isFalse);
  });

  test('an already paused listener never auto-resumes', () {
    final policy = CallAutoResumePolicy();
    policy.begin(wasPlaying: false, callLike: true);
    expect(policy.end(), isFalse);
  });

  test('manual pause during an incoming call cancels auto resume', () {
    final policy = CallAutoResumePolicy();
    policy.begin(wasPlaying: true, callLike: true);
    policy.cancel();
    expect(policy.end(), isFalse);
  });

  test('Bluetooth route and other noisy events never auto resume', () {
    final policy = CallAutoResumePolicy();
    policy.begin(wasPlaying: true, callLike: true);
    policy.cancel();
    expect(policy.end(), isFalse);
    policy.begin(wasPlaying: true, callLike: false);
    expect(policy.end(), isFalse);
  });

  test('duck-only and stray interruption-end signals cannot auto play', () {
    final policy = CallAutoResumePolicy();
    expect(policy.end(), isFalse);
    policy.begin(wasPlaying: true, callLike: false);
    expect(policy.end(), isFalse);
  });

  test('track switching cancels a prior call resume', () {
    final policy = CallAutoResumePolicy();
    policy.begin(wasPlaying: true, callLike: true);
    policy.cancel();
    expect(policy.end(), isFalse);
    policy.begin(wasPlaying: true, callLike: true);
    expect(policy.end(), isTrue);
  });
}
