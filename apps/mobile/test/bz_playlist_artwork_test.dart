import 'package:breezze/widgets/bz_playlist_artwork.dart';
import 'package:breezze/widgets/bz_brand_icons.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('playlist without cover images shows four genuine Breezze placeholders',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: const Scaffold(
        body: Center(
          child: BzPlaylistArtwork(artworkUrls: [], size: 200),
        ),
      ),
    ));
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(BzBnoteMark), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('one actual source artwork is full bleed, not replicated fake collage',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: const Scaffold(
        body: BzPlaylistArtwork(
          artworkUrls: ['https://example.test/song-cover.jpg'],
          size: 128,
        ),
      ),
    ));
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('invalid or unsecured album-art URLs never download into a cover',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: const Scaffold(
        body: BzPlaylistArtwork(
          artworkUrls: ['file:///private.jpg', 'http://unsafe.test/album.png'],
          size: 128,
        ),
      ),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
