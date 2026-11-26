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
}
