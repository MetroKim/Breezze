import 'package:breezze/features/catalog/catalog_detail_screens.dart';
import 'package:breezze/app/bootstrap.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('saved artist page shows real saved songs and honest catalog gaps',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: bzLightTheme(),
          home: const ArtistDetailScreen(
            artist: 'Test Artist',
            savedTracks: [
              FavoriteTrack(
                id: 'track-1',
                title: 'Saved Song',
                artist: 'Test Artist',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Test Artist'), findsWidgets);
    expect(find.text('Saved Song'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Essential Albums'), 260);
    expect(find.text('Essential Albums'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Upcoming Concerts'), 260);
    expect(find.text('Upcoming Concerts'), findsOneWidget);
    expect(
      find.textContaining('Verified artist catalog data is required'),
      findsWidgets,
    );
  });

  testWidgets('album detail renders its canonical metadata and tracklist',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: bzLightTheme(),
          home: const AlbumDetailScreen(
            canonicalAlbumId: 'album-1',
            title: 'Test Album',
            artist: 'Test Artist',
            releaseDate: '2026',
            tracks: [
              TrackInfo(
                id: 'track-1',
                title: 'Opening Track',
                artist: 'Test Artist',
                duration: Duration(minutes: 3, seconds: 12),
              ),
            ],
            credits: ['Produced by Test Producer'],
          ),
        ),
      ),
    );

    expect(find.text('Test Album'), findsOneWidget);
    expect(find.text('Opening Track'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Produced by Test Producer'), 260);
    expect(find.text('Produced by Test Producer'), findsOneWidget);
  });
}
