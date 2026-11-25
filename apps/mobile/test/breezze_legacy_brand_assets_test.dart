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
