import 'package:breezze/widgets/bz_branded_app_bar.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('catalog title keeps Breezze as the app identity',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: const Scaffold(
        appBar: BzBrandedAppBar(
          title: 'Discover',
          subtitle: 'YouTube Music public catalog',
        ),
      ),
    ));
    expect(find.text('Breezze'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('YouTube Music public catalog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow handset and large text retain a usable Breezze title',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          appBar: BzBrandedAppBar(
            title: 'Official music video discovery',
            subtitle: 'YouTube Music',
          ),
        ),
      ),
    ));
    // One backgroundless official mark + wordmark, alongside the truncated
    // page title. Never repeat the Breezze brand as a second headline.
    expect(find.text('Breezze'), findsOneWidget);
    expect(find.text('Official music video discovery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
