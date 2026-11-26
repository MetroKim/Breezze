import 'package:breezze/widgets/bz_morphing_brand_header.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host({MediaQueryData? media, VoidCallback? onSearch}) {
  return MaterialApp(
    theme: bzDarkTheme(),
    home: Scaffold(
      body: MediaQuery(
        data: media ?? const MediaQueryData(),
        child: CustomScrollView(
          slivers: [
            BzMorphingBrandHeader(
              actions: [
                IconButton(
                  tooltip: 'Search Breezze music',
                  onPressed: onSearch,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 1600)),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('official Breezze mark and name compress without app-icon background',
      (tester) async {
    await tester.pumpWidget(_host());
    expect(find.byKey(const Key('breezze-expanded-wordmark')), findsOneWidget);
    expect(find.byKey(const Key('breezze-compact-icon')), findsNothing);

    await tester.drag(
        find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('breezze-compact-icon')), findsOneWidget);
    expect(find.byKey(const Key('breezze-expanded-wordmark')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling back restores full Breezze wordmark', (tester) async {
    await tester.pumpWidget(_host());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('breezze-expanded-wordmark')), findsOneWidget);
    expect(find.byKey(const Key('breezze-compact-icon')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('morphing header keeps functional action visible', (tester) async {
    var searchOpens = 0;
    await tester.pumpWidget(_host(onSearch: () => searchOpens++));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -280));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search Breezze music'));
    expect(searchOpens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables the logo transition', (tester) async {
    await tester.pumpWidget(_host(
      media: const MediaQueryData(disableAnimations: true),
    ));
    final container = tester.widget<AnimatedContainer>(
      find.byKey(const Key('breezze-morphing-brand')),
    );
    expect(container.duration, Duration.zero);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('breezze-compact-icon')), findsOneWidget);
  });

  testWidgets('library/search compact brand uses transparent mark-and-name lockup',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: const Scaffold(
        body: Center(child: BzCompactBrandMark(size: 38)),
      ),
    ));
    expect(find.byKey(const Key('breezze-transparent-brand')), findsOneWidget);
    expect(find.byType(BzCompactBrandMark), findsOneWidget);
    expect(find.text('Breezze'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('desktop sidebar prevents duplicated Breezze wordmarks',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opens = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: BzSidebarBrandOwner(
        visible: true,
        child: Scaffold(
        body: CustomScrollView(
          slivers: [
            BzMorphingBrandHeader(
              sidebarBrandOnDesktop: true,
              actions: [
                IconButton(
                  tooltip: 'Search Breezze music',
                  icon: const Icon(Icons.search),
                  onPressed: () => opens++,
                ),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 1100)),
          ],
        ),
      ),
      ),
    ));
    expect(find.byKey(const Key('breezze-expanded-wordmark')), findsNothing);
    expect(find.byKey(const Key('breezze-compact-icon')), findsNothing);
    await tester.tap(find.byTooltip('Search Breezze music'));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

}
