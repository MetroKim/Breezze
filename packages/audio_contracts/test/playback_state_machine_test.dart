import 'package:audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaybackStateMachine (§53.2)', () {
    test('idle → resolving → loading → buffering → playing', () {
      final m = PlaybackStateMachine();
      expect(m.state, PlaybackState.idle);
      m.dispatch(StartRequested('t1'));
      expect(m.state, PlaybackState.resolving);
      m.dispatch(SourceResolved('t1', 'https://stream'));
      expect(m.state, PlaybackState.loading);
      m.dispatch(MediaReady());
      expect(m.state, PlaybackState.buffering);
      m.dispatch(PlayPressed());
      expect(m.state, PlaybackState.playing);
    });

    test('playing ↔ paused', () {
      final m = PlaybackStateMachine()
        ..dispatch(StartRequested('t1'))
        ..dispatch(SourceResolved('t1', 'url'))
        ..dispatch(MediaReady())
        ..dispatch(PlayPressed());
      m.dispatch(PausePressed());
      expect(m.state, PlaybackState.paused);
      m.dispatch(PlayPressed());
      expect(m.state, PlaybackState.playing);
    });

    test('playing → seeking → playing', () {
      final m = PlaybackStateMachine()
        ..dispatch(StartRequested('t1'))
        ..dispatch(SourceResolved('t1', 'url'))
        ..dispatch(MediaReady())
        ..dispatch(PlayPressed());
      m.dispatch(SeekRequested(const Duration(seconds: 30)));
      expect(m.state, PlaybackState.seeking);
      m.dispatch(SeekCompleted());
      expect(m.state, PlaybackState.playing);
    });

    test('playing → interrupted → (ended) paused', () {
      final m = PlaybackStateMachine()
        ..dispatch(StartRequested('t1'))
        ..dispatch(SourceResolved('t1', 'url'))
        ..dispatch(MediaReady())
        ..dispatch(PlayPressed());
      m.dispatch(InterruptionDetected());
      expect(m.state, PlaybackState.interrupted);
      m.dispatch(InterruptionEnded());
      expect(m.state, PlaybackState.paused);
    });

    test('playing → offline → restored paused', () {
      final m = PlaybackStateMachine()
        ..dispatch(StartRequested('t1'))
        ..dispatch(SourceResolved('t1', 'url'))
        ..dispatch(MediaReady())
        ..dispatch(PlayPressed());
      m.dispatch(ConnectionLost());
      expect(m.state, PlaybackState.offline);
      m.dispatch(ConnectionRestored());
      expect(m.state, PlaybackState.paused);
    });

    test('playing → ended', () {
      final m = PlaybackStateMachine()
        ..dispatch(StartRequested('t1'))
        ..dispatch(SourceResolved('t1', 'url'))
        ..dispatch(MediaReady())
        ..dispatch(PlayPressed());
      m.dispatch(TrackCompleted());
      expect(m.state, PlaybackState.ended);
    });

    test('resolution failure → failed; can restart', () {
      final m = PlaybackStateMachine();
      m.dispatch(StartRequested('t1'));
      m.dispatch(SourceResolutionFailed('RIGHTS_NOT_AVAILABLE'));
      expect(m.state, PlaybackState.failed);
      m.dispatch(StartRequested('t1'));
      expect(m.state, PlaybackState.resolving);
    });
  });
}
