import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('filter stays operable at 200% text scale with selected state',
      (tester) async {
    var activations = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(350, 720),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: BzFilterPill(
                label: 'Library',
                active: true,
                onTap: () => activations++,
              ),
            ),
          ),
        ),
      ),
    ));
    expect(find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.selected == true &&
        widget.properties.label == 'Library'), findsOneWidget);
    expect(tester.getSize(find.byType(BzFilterPill)).height,
        greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Library'));
    expect(activations, 1);
  });


  testWidgets('filter pill provides an accessible touch target and activates',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: Scaffold(
        body: Center(
          child: BzFilterPill(
            label: 'Music Videos',
            active: true,
            onTap: () => taps++,
          ),
        ),
      ),
    ));
    expect(find.text('Music Videos'), findsOneWidget);
    expect(tester.getSize(find.byType(BzFilterPill)).height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.text('Music Videos'));
    expect(taps, 1);
  });
}
