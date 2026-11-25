import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:breezze/widgets/bz_brand_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('previous Breezze white and black vector lockups are retained', () async {
    for (final path in <String>[
      'assets/icons/breezze-logo-white.svg',
      'assets/icons/breezze-logo-black.svg',
    ]) {
      final svg = await rootBundle.loadString(path);
      expect(svg, contains('viewBox="0 0 1600 400"'), reason: path);
      expect(svg, contains('Breezze'), reason: path);
      expect(svg, contains('M162,183'), reason: path);
    }
  });

  test('official pixel B is preserved across the monochrome asset family', () async {
    const basePath = 'assets/icons/breezze-app-icon.svg';
    final source = await rootBundle.loadString(basePath);
    final dark = await rootBundle.loadString(
      'assets/icons/breezze-app-monochrome-dark.svg',
    );
    final light = await rootBundle.loadString(
      'assets/icons/breezze-app-monochrome-light.svg',
    );
    final originalMark = await rootBundle.loadString(
      'assets/icons/breezze-symbol-black.svg',
    );
    final adaptiveMark = await rootBundle.loadString(
      'assets/icons/breezze-symbol-monochrome-adaptive.svg',
    );
    final paths = RegExp(r'<path[^>]*d="([^"]+)"');
    final basePaths = paths.allMatches(source).map((m) => m.group(1)).toList();
    expect(basePaths.length, 2);
    for (final (asset, background, foreground) in [
      (dark, '#000000', '#FFFFFF'),
      (light, '#FFFFFF', '#000000'),
    ]) {
      expect(paths.allMatches(asset).map((m) => m.group(1)).toList(),
          basePaths, reason: 'Official pixel-B paths must not be redrawn');
      expect(asset, contains('rx="218" fill="$background"'));
      expect(asset, contains('color="$foreground"'));
      expect(asset, contains('viewBox="0 0 1024 1024"'));
    }
    expect(paths.allMatches(adaptiveMark).map((m) => m.group(1)).toList(),
        paths.allMatches(originalMark).map((m) => m.group(1)).toList());
    expect(adaptiveMark, contains('color="currentColor"'));
    expect(source, contains('fill="#050505"'),
        reason: 'The historical official icon remains untouched');
  });

  testWidgets('monochrome app tile supports both themes without error',
      (tester) async {
    for (final isDark in <bool>[false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: isDark ? ThemeData.dark() : ThemeData.light(),
        home: const Scaffold(
          body: Center(child: BzMonochromeAppIcon(size: 60)),
        ),
      ));
      await tester.pump();
      expect(find.byType(BzMonochromeAppIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('current monochrome brand mark remains functional',
      (tester) async {
    for (final isDark in <bool>[false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: isDark ? ThemeData.dark() : ThemeData.light(),
        home: const Scaffold(body: Center(child: BzBnoteMark(size: 48))),
      ));
      await tester.pump();
      expect(find.byType(BzBnoteMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
