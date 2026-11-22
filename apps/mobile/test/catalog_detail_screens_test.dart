import 'package:breezze/features/catalog/catalog_detail_screens.dart';
import 'package:breezze/app/bootstrap.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:breezze/features/player/player_controller.dart';
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
    await tester.pumpAndSettle();

    expect(find.text('Test Artist'), findsWidgets);
    expect(find.text('Saved Song'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Apple catalog discography'), 260);
    expect(find.text('Apple catalog discography'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Upcoming Concerts'), 260);
    expect(find.text('Upcoming Concerts'), findsOneWidget);
    expect(
      find.text('Retry concert listings'),
      findsOneWidget,
    );
  });

  testWidgets('track detail shows song metadata without inventing an album',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: bzLightTheme(),
          home: TrackDetailScreen(
            track: TrackInfo(
              id: 'bz:track-1',
              title: 'Search Result Song',
              artist: 'Search Result Artist',
              duration: Duration(minutes: 3, seconds: 8),
            ),
            relatedTracks: [
              TrackInfo(
                id: 'bz:track-1',
                title: 'Search Result Song',
                artist: 'Search Result Artist',
              ),
              TrackInfo(
                id: 'bz:track-2',
                title: 'Another Song',
                artist: 'Search Result Artist',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search Result Song'), findsOneWidget);
    expect(find.text('Search Result Artist'), findsWidgets);
    expect(find.text('Add to Library'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Album'), 240);
    expect(find.text('Album'), findsOneWidget);
    expect(find.textContaining('Verified album relationship'), findsNothing);
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
