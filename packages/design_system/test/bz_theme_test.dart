import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double _contrastRatio(Color a, Color b) {
  final light = a.computeLuminance() > b.computeLuminance()
      ? a.computeLuminance() : b.computeLuminance();
  final dark = a.computeLuminance() < b.computeLuminance()
      ? a.computeLuminance() : b.computeLuminance();
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  test('Apple devices use OS font proxies without bundling SF Pro', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      final theme = bzLightTheme(platform: platform);
      expect(theme.platform, platform);
      expect(theme.textTheme.displayMedium?.fontFamily, 'CupertinoSystemDisplay');
      expect(theme.textTheme.headlineLarge?.fontFamily, 'CupertinoSystemDisplay');
      expect(theme.textTheme.titleLarge?.fontFamily, 'CupertinoSystemDisplay');
      expect(theme.textTheme.titleMedium?.fontFamily, 'CupertinoSystemText');
      expect(theme.textTheme.bodyLarge?.fontFamily, 'CupertinoSystemText');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'CupertinoSystemText');
      expect(theme.bzBackground, BzThemeColors.light.background);
    }
    final android = bzLightTheme(platform: TargetPlatform.android);
    expect(android.platform, TargetPlatform.android);
    expect(android.textTheme.displayMedium?.fontFamily,
        isNot('CupertinoSystemDisplay'));
    expect(android.textTheme.bodyMedium?.fontFamily,
        isNot('CupertinoSystemText'));
  });


  test('Breezze original light/dark palette clears WCAG AA body text contrast', () {
    for (final theme in [bzLightTheme(), bzDarkTheme()]) {
      final palette = theme.bz;
      for (final surface in [
        palette.background, palette.surface1, palette.surface2,
        palette.elevated,
      ]) {
        expect(_contrastRatio(palette.text1, surface), greaterThanOrEqualTo(4.5),
            reason: 'Primary text on Breezze surface must stay readable');
        expect(_contrastRatio(palette.text2, surface), greaterThanOrEqualTo(4.5),
            reason: 'Secondary text on Breezze surface must stay readable');
      }
      // Focus borders are the existing neutral Breezze accent, not green.
      expect(_contrastRatio(palette.accent, palette.surface1),
          greaterThanOrEqualTo(3.0));
      expect(_contrastRatio(palette.accent, palette.background),
          greaterThanOrEqualTo(3.0));
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
