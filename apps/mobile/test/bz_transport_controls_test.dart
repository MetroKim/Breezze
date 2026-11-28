import 'package:breezze/widgets/bz_transport_controls.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('wide transport retains five controls in the glass capsule',
      (tester) async {
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(
          width: 380,
          child: BzTransportControls(
            playing: false,
            onPrevious: () {},
            onNext: () {},
            onTogglePlayPause: () => played++,
            onShuffle: () {},
            onRepeat: () {},
          ),
        )),
      ),
    ));
    expect(find.byTooltip('Shuffle'), findsOneWidget);
    expect(find.byTooltip('Repeat'), findsOneWidget);
    expect(find.byType(BzGlassContainer), findsOneWidget);
    expect(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label == 'Resume playback' &&
        widget.properties.button == true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label == 'Resume playback'));
    expect(played, 1);
  });

  testWidgets('narrow layout preserves shuffle and repeat below play capsule',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(
          width: 260,
          child: BzTransportControls(
            playing: true,
            onPrevious: () {},
            onNext: () {},
            onTogglePlayPause: () {},
            onShuffle: () {},
            onRepeat: () {},
          ),
        )),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Shuffle'), findsOneWidget);
    expect(find.byTooltip('Repeat'), findsOneWidget);
    final next = tester.getTopLeft(find.byTooltip('Next track'));
    final shuffle = tester.getTopLeft(find.byTooltip('Shuffle'));
    expect(shuffle.dy, greaterThan(next.dy),
        reason: 'Secondary actions move below primary playback controls');
  });

  testWidgets('large text chooses accessible transport ordering',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Center(child: SizedBox(
            width: 380,
            child: BzTransportControls(
              playing: false,
              onPrevious: () {},
              onNext: () {},
              onTogglePlayPause: () {},
              onShuffle: () {},
              onRepeat: () {},
            ),
          )),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final previous = tester.getTopLeft(find.byTooltip('Previous track'));
    final repeat = tester.getTopLeft(find.byTooltip('Repeat'));
    expect(repeat.dy, greaterThan(previous.dy));
  });

  testWidgets('transport meets Android/iOS tap targets and semantic labels',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        theme: bzLightTheme(),
        home: Scaffold(
          body: Center(child: SizedBox(
            width: 380,
            child: BzTransportControls(
              playing: true,
              onPrevious: () {},
              onNext: () {},
              onTogglePlayPause: () {},
              onShuffle: () {},
              onRepeat: () {},
            ),
          )),
        ),
      ));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('previous and next controls remain distinct without rewind',
      (tester) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(
          width: 280,
          child: BzTransportControls(
            playing: true,
            onPrevious: () => previous++,
            onNext: () => next++,
            onTogglePlayPause: () {},
            onShuffle: () {},
            onRepeat: () {},
          ),
        )),
      ),
    ));
    expect(find.byTooltip('Previous track'), findsOneWidget);
    expect(find.byTooltip('Next track'), findsOneWidget);
    expect(find.byTooltip('Rewind 10 seconds'), findsNothing);
    await tester.tap(find.byTooltip('Previous track'));
    expect(previous, 1);
    expect(next, 0);
    await tester.tap(find.byTooltip('Next track'));
    expect(previous, 1);
    expect(next, 1);
    expect(tester.takeException(), isNull);
  });


  testWidgets('ten-second rewind and forward are independently tappable',
      (tester) async {
    var backwards = 0;
    var forwards = 0;
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(
          width: 260,
          child: BzTransportControls(
            playing: true,
            onPrevious: () => previous++,
            onNext: () => next++,
            onTogglePlayPause: () {},
            onShuffle: () {},
            onRepeat: () {},
            onRewindTen: () => backwards++,
            onForwardTen: () => forwards++,
          ),
        )),
      ),
    ));
    expect(find.byTooltip('Previous track'), findsOneWidget);
    expect(find.byTooltip('Next track'), findsOneWidget);
    expect(find.byTooltip('Rewind 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    await tester.tap(find.byTooltip('Rewind 10 seconds'));
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    expect(backwards, 1);
    expect(forwards, 1);
    expect(previous, 0);
    expect(next, 0);
    expect(tester.takeException(), isNull);
  });
}
