import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(
  Widget child, {
  ThemeData? theme,
  MediaQueryData? media,
}) {
  Widget body = Scaffold(body: Center(child: child));
  if (media != null) {
    body = MediaQuery(data: media, child: body);
  }
  return MaterialApp(theme: theme ?? bzDarkTheme(), home: body);
}

const _glassChild = SizedBox(height: 48, width: 240);

void main() {
  testWidgets('budget grants blur to at most two surfaces', (tester) async {
    await tester.pumpWidget(
      _host(
        const BzGlassBudgetScope(
          child: Column(
            children: [
              BzGlass(state: BzGlassState.pillScrolled, child: _glassChild),
              BzGlass(state: BzGlassState.pillScrolled, child: _glassChild),
              BzGlass(state: BzGlassState.pillScrolled, child: _glassChild),
            ],
          ),
        ),
      ),
    );

    // NFR-007: max 2 visible blurred surfaces — the third demotes to solid.
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    // Demotion is a solid surface, not a disappearance.
    expect(find.byType(SizedBox), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('releasing a surface restores the budget to the next one',
      (tester) async {
    var showFirst = true;
    Widget build() => _host(
          BzGlassBudgetScope(
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  if (showFirst)
                    const BzGlass(
                      key: Key('g0'),
                      state: BzGlassState.pillScrolled,
                      child: _glassChild,
                    ),
                  const BzGlass(
                    key: Key('g1'),
                    state: BzGlassState.pillScrolled,
                    child: _glassChild,
                  ),
                  const BzGlass(
                    key: Key('g2'),
                    state: BzGlassState.pillScrolled,
                    child: _glassChild,
                  ),
                ],
              ),
            ),
          ),
        );

    await tester.pumpWidget(build());
    expect(find.byType(BackdropFilter), findsNWidgets(2));

    showFirst = false;
    await tester.pumpWidget(build());
    // Flush the post-frame budget notification and rebuild.
    await tester.pump();

    expect(find.byKey(const Key('g0')), findsNothing);
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear state renders tint and border only, no blur',
      (tester) async {
    await tester.pumpWidget(
      _host(const BzGlass(state: BzGlassState.clear, child: _glassChild)),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('high contrast collapses glass to a solid surface',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const BzGlass(state: BzGlassState.pillScrolled, child: _glassChild),
        media: MediaQueryData(highContrast: true),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('reduce motion collapses glass to a solid surface',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const BzGlass(state: BzGlassState.mediaOverlay, child: _glassChild),
        media: MediaQueryData(disableAnimations: true),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('glass renders without a scope for standalone callers',
      (tester) async {
    await tester.pumpWidget(
      _host(const BzGlass(state: BzGlassState.pillScrolled, child: _glassChild)),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass content color follows surface luminance', (tester) async {
    Color? captured;

    await tester.pumpWidget(
      MaterialApp(
        theme: bzDarkTheme(),
        home: Builder(
          builder: (context) {
            captured = bzGlassContentColor(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, const Color(0xFFFFFFFF));

    await tester.pumpWidget(
      MaterialApp(
        theme: bzLightTheme(),
        home: Builder(
          builder: (context) {
            captured = bzGlassContentColor(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, const Color(0xFF000000));
  });
}
