import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('light and dark Breezze themes share consistent component geometry', () {
    for (final theme in [bzLightTheme(), bzDarkTheme()]) {
      final colors = theme.bz;
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(theme.appBarTheme.backgroundColor, colors.background);
      expect(theme.appBarTheme.foregroundColor, colors.text1);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.textTheme.displayMedium?.fontSize, BzType.display);
      expect(theme.textTheme.titleLarge?.fontSize, BzType.title2);
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.inputDecorationTheme.fillColor, colors.surface1);
      expect(theme.inputDecorationTheme.focusedBorder, isA<OutlineInputBorder>());
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({}),
        const Size(44, 48),
      );
      expect(
        theme.textButtonTheme.style?.minimumSize?.resolve({}),
        const Size(44, 44),
      );
      expect(
        theme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size(44, 44),
      );
      expect(theme.cardTheme.color, colors.surface1);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    }
  });

  testWidgets('unified input fields and buttons work in both palettes',
      (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? bzDarkTheme() : bzLightTheme(),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 240,
                    child: TextField(
                      decoration: InputDecoration(labelText: 'Email'),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
