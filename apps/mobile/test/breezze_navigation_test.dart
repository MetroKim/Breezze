import 'package:breezze/app/breezze_navigation.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Breezze details follow $platform navigation conventions',
        (tester) async {
      Route<void>? captured;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final route = breezzePageRoute<void>(
                context: context,
                builder: (_) => const Scaffold(
                  body: Center(child: Text('Breezze detail')),
                ),
              );
              captured = route;
              Navigator.of(context).push(route);
            },
            child: const Text('Open artist'),
          ),
        )),
      ));
      await tester.tap(find.text('Open artist'));
      if (platform == TargetPlatform.iOS) {
        expect(captured, isA<CupertinoPageRoute<void>>());
      } else {
        expect(captured, isA<MaterialPageRoute<void>>());
      }
      await tester.pumpAndSettle();
      expect(find.text('Breezze detail'), findsOneWidget);
    });
  }

  testWidgets('reduced motion uses zero-duration transitions', (tester) async {
    Route<void>? captured;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final route = breezzePageRoute<void>(
                context: context,
                fullscreenDialog: true,
                builder: (_) => const Scaffold(
                  body: Center(child: Text('Now Playing')),
                ),
              );
              captured = route;
              Navigator.of(context).push(route);
            },
            child: const Text('Open player'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('Open player'));
    expect(captured, isA<PageRouteBuilder<void>>());
    final route = captured! as PageRouteBuilder<void>;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(route.fullscreenDialog, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);
  });
}
