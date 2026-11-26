import 'package:breezze/widgets/bz_pinned_mood_rail.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const moods = <String>['Energy', 'Focus', 'Relax', 'Workout', 'Chill', 'Commute'];

  Widget host(ValueChanged<String> onMood, {
    MediaQueryData? accessibility,
  }) => MaterialApp(
    theme: bzDarkTheme(),
    home: Scaffold(
      body: MediaQuery(
        data: accessibility ?? const MediaQueryData(),
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
            BzPinnedMoodRail(
              moods: moods,
              onMoodSelected: onMood,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 1600)),
          ],
        ),
      ),
    ),
  );

  testWidgets('mood rail remains pinned after scroll and triggers real callback',
      (tester) async {
    String? selected;
    await tester.pumpWidget(host((value) => selected = value));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('breezze-pinned-mood-rail')), findsOneWidget);
    await tester.tap(find.text('Focus'));
    expect(selected, 'Focus');
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phone supports horizontal mood navigation',
      (tester) async {
    tester.view.physicalSize = const Size(300, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selected;
    await tester.pumpWidget(host((value) => selected = value,
      accessibility: const MediaQueryData(
        textScaler: TextScaler.linear(1.5),
        disableAnimations: true,
        highContrast: true,
      ),
    ));
    await tester.drag(
      find.byKey(const Key('breezze-pinned-mood-rail')),
      const Offset(-650, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commute'));
    expect(selected, 'Commute');
    expect(tester.takeException(), isNull);
  });
}
