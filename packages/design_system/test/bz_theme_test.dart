import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a >= b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  test('semantic secondary and tertiary small text meets WCAG AA contrast', () {
    const threshold = 4.5;
    final schemes = <String, (List<Color>, List<Color>)>{
      'light': (
        [BzColorsLight.textSecondary, BzColorsLight.textTertiary],
        [BzColorsLight.background, BzColorsLight.surfacePrimary,
         BzColorsLight.surfaceSecondary],
      ),
      'dark': (
        [BzColorsDark.textSecondary, BzColorsDark.textTertiary],
        [BzColorsDark.background, BzColorsDark.surfacePrimary,
         BzColorsDark.surfaceSecondary],
      ),
    };
    for (final entry in schemes.entries) {
      for (final foreground in entry.value.$1) {
        for (final surface in entry.value.$2) {
          expect(_contrast(foreground, surface), greaterThanOrEqualTo(threshold),
              reason: '${entry.key}: text $foreground on surface $surface');
        }
      }
    }
  });

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
