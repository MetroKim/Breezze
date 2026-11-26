import 'package:breezze/widgets/bz_brand_icons.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('official Breezze identity uses transparent SVG symbol and real name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: const Scaffold(
        body: Center(child: BzBrandLockup(markHeight: 34)),
      ),
    ));
    expect(find.text('Breezze'), findsOneWidget);
    expect(find.byType(BzBnoteMark), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
