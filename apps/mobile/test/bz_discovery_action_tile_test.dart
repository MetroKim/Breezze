import 'package:breezze/widgets/bz_discovery_action_tile.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('discovery tile navigates rather than presenting a fake button',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 330,
            child: BzDiscoveryActionTile(
              label: 'Music videos',
              description: 'Official video search',
              iconName: 'video',
              onTap: () => opened = true,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Music videos'), findsOneWidget);
    expect(find.text('Official video search'), findsOneWidget);
    await tester.tap(find.text('Music videos'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery tile remains operable in large text mode',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 360,
              child: BzDiscoveryActionTile(
                label: 'Explore artists',
                description: 'Find artist profiles',
                iconName: 'user-round',
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Explore artists'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
