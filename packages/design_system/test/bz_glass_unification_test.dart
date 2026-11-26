import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
        theme: bzDarkTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('legacy glass facade uses exactly one canonical BzGlass engine',
      (tester) async {
    await tester.pumpWidget(host(
      const BzGlassContainer(
        radius: 16,
        blur: 15,
        child: SizedBox(width: 220, height: 52),
      ),
    ));
    expect(find.byType(BzGlass), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two surface budget applies to legacy facade as well',
      (tester) async {
    await tester.pumpWidget(host(const BzGlassBudgetScope(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BzGlassContainer(radius: 16, child: SizedBox(width: 100, height: 52)),
          BzGlassContainer(radius: 16, child: SizedBox(width: 100, height: 52)),
          BzGlassContainer(radius: 16, child: SizedBox(width: 100, height: 52)),
        ],
      ),
    )));
    expect(find.byType(BzGlass), findsNWidgets(3));
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables legacy facade blur', (tester) async {
    await tester.pumpWidget(host(
      const BzGlassContainer(
        radius: 18,
        child: SizedBox(width: 100, height: 44),
      ),
      reduced: true,
    ));
    expect(find.byType(BzGlass), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
