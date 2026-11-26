import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _Deck implements OnlineAutomixDeck {
  final levels = <double>[];
  var plays = 0;
  var stops = 0;
  bool failVolume = false;
  bool failPlayAfterStart = false;
  void Function(double)? onVolume;

  @override
  Future<void> setVolume(double value) async {
    if (failVolume) throw StateError('decoder failed');
    levels.add(value);
    onVolume?.call(value);
  }

  @override
  Future<void> play() async {
    plays++;
    if (failPlayAfterStart) throw StateError('native play failed after start');
  }

  @override
  Future<void> stop() async { stops++; }
}

const _transition = MixTransition(
  beatMatched: false,
  tempoFactor: 1,
  transitionMs: 1000,
  doubleTimeFold: false,
);

void main() {
  test('two decks overlap with a bounded equal-power transition', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    final waits = <Duration>[];
    await const OnlineAutomixRenderer().render(
      outgoing: outgoing,
      incoming: incoming,
      plan: _transition,
      bothSourcesAuthorized: () => true,
      steps: 4,
      delay: (d) async { waits.add(d); },
    );
    expect(incoming.plays, 1);
    expect(outgoing.stops, 1);
    expect(incoming.stops, 0);
    expect(waits, List.filled(4, const Duration(milliseconds: 250)));
    expect(outgoing.levels.last, closeTo(0, 0.00001));
    expect(incoming.levels.first, 0);
    expect(incoming.levels.last, 1);
    expect(outgoing.levels[0], closeTo(0.923879, 0.001));
    expect(incoming.levels[1], closeTo(0.382683, 0.001));
  });

  test('revoked rights stop both decks before leaked audio', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    var authorized = true;
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () => authorized,
        steps: 4,
        delay: (_) async { authorized = false; },
      ),
      throwsA(isA<AutomixAuthorizationLost>()),
    );
    expect(outgoing.stops, 1);
    expect(incoming.stops, 1);
  });

  test('decoder failure silences incoming and restores licensed outgoing', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    var ticks = 0;
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () => true,
        steps: 4,
        delay: (_) async {
          if (++ticks == 2) incoming.failVolume = true;
        },
      ),
      throwsStateError,
    );
    expect(incoming.stops, 1);
    expect(outgoing.stops, 0);
    expect(outgoing.levels.last, 1);
  });

  test('a transition cannot play without permission', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () => false,
      ),
      throwsA(isA<AutomixAuthorizationLost>()),
    );
    expect(incoming.plays, 0);
  });

  test('identical decks or unreasonable fade envelopes fail closed', () async {
    final same = _Deck();
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: same,
        incoming: same,
        plan: _transition,
        bothSourcesAuthorized: () => true,
      ),
      throwsArgumentError,
    );
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: _Deck(),
        incoming: _Deck(),
        plan: _transition,
        bothSourcesAuthorized: () => true,
        steps: 0,
      ),
      throwsArgumentError,
    );
  });

  test('native play throwing after start still silences incoming deck', () async {
    final outgoing = _Deck();
    final incoming = _Deck()..failPlayAfterStart = true;
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () => true,
      ),
      throwsStateError,
    );
    expect(incoming.plays, 1);
    expect(incoming.stops, 1);
    expect(outgoing.stops, 0);
    expect(outgoing.levels.last, 1);
  });

  test('checker exceptions are denied and both decks are stopped', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    var checkerUnavailable = false;
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () {
          if (checkerUnavailable) throw StateError('auth service unavailable');
          return true;
        },
        steps: 4,
        delay: (_) async { checkerUnavailable = true; },
      ),
      throwsA(isA<AutomixAuthorizationLost>()),
    );
    expect(incoming.stops, 1);
    expect(outgoing.stops, 1);
  });

  test('rights denial before overlap stops the outgoing recording', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () => false,
      ),
      throwsA(isA<AutomixAuthorizationLost>()),
    );
    expect(incoming.plays, 0);
    expect(incoming.stops, 1);
    expect(outgoing.stops, 1);
  });

  test('last-step grant revocation stops both decks after their gain writes', () async {
    final outgoing = _Deck();
    final incoming = _Deck();
    var authorized = true;
    incoming.onVolume = (level) {
      if (level >= 1) authorized = false;
    };
    await expectLater(
      const OnlineAutomixRenderer().render(
        outgoing: outgoing,
        incoming: incoming,
        plan: _transition,
        bothSourcesAuthorized: () => authorized,
        steps: 4,
        delay: (_) async {},
      ),
      throwsA(isA<AutomixAuthorizationLost>()),
    );
    expect(incoming.stops, 1);
    expect(outgoing.stops, 1);
  });
}
