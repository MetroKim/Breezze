import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('track skeleton renders with reduced motion enabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bzLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: BzSkeletonTrackRow(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BzSkeleton), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive bottom clearance adapts to desktop width',
      (tester) async {
    double? compactInset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              compactInset = BzBreakpoints.bottomClearance(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(compactInset, 180);

    double? desktopInset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: Builder(
            builder: (context) {
              desktopInset = BzBreakpoints.bottomClearance(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(desktopInset, 24);
  });
}
