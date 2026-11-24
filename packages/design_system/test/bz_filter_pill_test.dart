import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
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
