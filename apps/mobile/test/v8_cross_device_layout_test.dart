import 'package:breezze/widgets/bz_discovery_action_tile.dart';
import 'package:breezze/widgets/bz_discovery_spotlight.dart';
import 'package:breezze/widgets/bz_morphing_brand_header.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget buildUi(TargetPlatform platform, void Function() open) => MaterialApp(
  theme: bzDarkTheme(platform: platform),
  home: Scaffold(
    body: CustomScrollView(
      slivers: [
        BzMorphingBrandHeader(
          actions: [
            IconButton(
              tooltip: 'Search Breezze music',
              onPressed: open,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: 'Account and profile',
              onPressed: open,
              icon: const Icon(Icons.person),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: open,
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              BzDiscoverySpotlight(
                eyebrow: 'Breezze discovery',
                title: 'Find something new',
                description: 'Browse real songs and official music videos.',
                actionLabel: 'Explore New',
                onAction: open,
              ),
              const SizedBox(height: 20),
              BzDiscoveryActionTile(
                label: 'Music videos',
                description: 'Official video search',
                iconName: 'video',
                onTap: open,
              ),
              const SizedBox(height: 1200),
            ]),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  const platformsAndWidths = <(TargetPlatform, double)>[
    (TargetPlatform.android, 320),
    (TargetPlatform.iOS, 390),
    (TargetPlatform.windows, 1280),
    (TargetPlatform.macOS, 1024),
    (TargetPlatform.linux, 768),
  ];

  for (final (platform, width) in platformsAndWidths) {
    testWidgets('$platform V8 adaptive branding, glass and navigation',
        (tester) async {
      tester.view.physicalSize = Size(width, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var navigations = 0;
      await tester.pumpWidget(buildUi(platform, () => navigations++));

      expect(find.byKey(const Key('breezze-expanded-wordmark')), findsOneWidget);
      await tester.tap(find.text('Explore New'));
      expect(navigations, 1);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('breezze-compact-icon')), findsOneWidget);
      await tester.tap(find.byTooltip('Search Breezze music'));
      expect(navigations, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('280dp foldable with accessibility settings avoids overflow',
      (tester) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(platform: TargetPlatform.android),
      home: const MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(1.8),
          disableAnimations: true,
          highContrast: true,
        ),
        child: Scaffold(
          body: CustomScrollView(
            slivers: [
              BzMorphingBrandHeader(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: BzDiscoveryActionTile(
                    label: 'Artists',
                    description: 'Artist pages and saved music',
                    iconName: 'user-round',
                    onTap: _noAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('breezze-expanded-wordmark')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noAction() {}
