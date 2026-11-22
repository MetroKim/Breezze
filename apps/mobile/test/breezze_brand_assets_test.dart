import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:breezze/widgets/bz_brand_icons.dart';

void main() {
  test('supplied Breezze vector brand assets are packaged and distinguishable',
      () async {
    for (final asset in [
      'assets/icons/breezze-app-icon.svg',
      'assets/icons/breezze-symbol-white.svg',
      'assets/icons/breezze-symbol-black.svg',
      'assets/icons/breezze-logo-white.svg',
      'assets/icons/breezze-logo-black.svg',
    ]) {
      final data = await rootBundle.loadString(asset);
      expect(data, contains('<svg'), reason: asset);
      expect(data, contains('M162,183'), reason: asset);
    }
    final icon = await rootBundle.loadString(
      'assets/icons/breezze-app-icon.svg',
    );
    expect(icon, contains('rx="218"'));
    expect(icon, contains('fill="#050505"'));
  });

  testWidgets('Breezze mark and wordmark render in both OS appearances',
      (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Column(
              children: const [
                BzBnoteMark(size: 40),
                BzRibbonLogo(width: 140),
                BzAppIcon(size: 48),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Breezze'), findsOneWidget);
      expect(find.byType(BzBnoteMark), findsOneWidget);
      expect(find.byType(BzAppIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
