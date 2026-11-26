import 'package:breezze/widgets/bz_release_shelf.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('official transparent logo preserves the exact source icon mark',
      () async {
    final lockup = await rootBundle.loadString(
      'assets/icons/breezze-official-lockup-transparent.svg',
    );
    final appIcon = await rootBundle.loadString(
      'assets/icons/breezze-app-icon.svg',
    );
    final pathPattern = RegExp(r'<path d="([^"]+)"');
    final officialPaths = pathPattern.allMatches(appIcon)
        .map((match) => match.group(1)).toList();
    final lockupPaths = pathPattern.allMatches(lockup)
        .map((match) => match.group(1)).toList();

    expect(lockupPaths, officialPaths,
        reason: 'The logo must reuse the original mark geometry');
    expect(lockup, contains('>Breezze</text>'));
    expect(lockup, isNot(contains('<rect')),
        reason: 'The wordmark is backgroundless, not an app icon');
  });

  testWidgets('fresh releases show source artist names and open a real route',
      (tester) async {
    Map<String, String>? opened;
    final source = <String, String>{
      'title': 'Example album',
      'artist': 'Example artist',
      'artworkUrl': 'https://example.com/real-source-image.jpg',
    };
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: 360,
            child: BzReleaseShelf(
              items: [source],
              onOpen: (item) => opened = item,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Fresh releases'), findsOneWidget);
    expect(find.text('Example album'), findsOneWidget);
    expect(find.text('Example artist'), findsOneWidget);
    await tester.tap(find.text('Example album'));
    expect(opened, source);
    expect(tester.takeException(), isNull);
  });
}
