import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('ZIP-inspired atmosphere preserves its content in dark mode',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bzDarkTheme(),
        home: const Scaffold(
          body: BzAmbientBackdrop(child: Text('Now Playing')),
        ),
      ),
    );

    expect(find.text('Now Playing'), findsOneWidget);
    // Without an artwork source, no network request or full-screen blur.
    expect(find.byType(Image), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light palette retains text and avoids network artwork',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(
          body: BzAmbientBackdrop(child: Text('Artist')),
        ),
      ),
    );

    expect(find.text('Artist'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
