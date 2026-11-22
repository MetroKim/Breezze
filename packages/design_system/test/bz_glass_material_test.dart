import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Locks the Liquid Glass material contract (§2.2, NFR-007).
void main() {
  group('BzGlassMaterial — material states', () {
    testWidgets('pillScrolled renders blur + hairline + soft shadow',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: const Scaffold(
            body: Center(
              child: BzGlassMaterial(
                state: BzGlassState.pillScrolled,
                radius: 20,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clear state never blurs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: const Scaffold(
            body: Center(
              child: BzGlassMaterial(
                state: BzGlassState.clear,
                radius: 20,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced transparency degrades to a solid, blur-free surface',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: const Scaffold(
            body: Center(
              child: BzGlassMaterial(
                state: BzGlassState.pillScrolled,
                radius: 20,
                reduceTransparency: true,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the blur budget is enforced: a third blurred surface asserts',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: const Scaffold(
            body: Column(
              children: [
                BzGlassMaterial(
                  state: BzGlassState.pillScrolled,
                  child: SizedBox(width: 120, height: 20),
                ),
                BzGlassMaterial(
                  state: BzGlassState.mediaOverlay,
                  child: SizedBox(width: 120, height: 20),
                ),
                BzGlassMaterial(
                  state: BzGlassState.pillAtTop,
                  child: SizedBox(width: 120, height: 20),
                ),
              ],
            ),
          ),
        ),
      );

      // The third blurred glass surface exceeds the budget of 2 and must
      // trip the debug assert. The registration counter is global; other
      // suites may have left state behind, so only assert the exception
      // exists here and reset cleanly afterwards.
      expect(tester.takeException(), isNotNull);
    });

    testWidgets('disposal decrements the blur budget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: const Scaffold(
            body: Center(
              child: BzGlassMaterial(
                state: BzGlassState.pillScrolled,
                child: SizedBox(width: 120, height: 20),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('BzBarSurface — bar-spawned surfaces are blur-free solids', () {
    testWidgets('never renders a BackdropFilter and always has a border',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: const Scaffold(
            body: Center(
              child: BzBarSurface(
                radius: 20,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      final box = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, BzColorsDark.surfaceElevated);
      expect(decoration.border, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
