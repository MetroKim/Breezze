import 'package:breezze/features/catalog/catalog_detail_screens.dart';
import 'package:breezze/app/bootstrap.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:breezze/features/player/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _InMemoryFavorites extends FavoritesStore {
  final saved = <String>{};

  String _key(String ownerId, String trackId) => '$ownerId::$trackId';

  @override
  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) async =>
      saved.contains(_key(ownerId, id));

  @override
  Future<bool> toggle(FavoriteTrack track, {String ownerId = 'guest'}) async {
    final key = _key(ownerId, track.id);
    if (!saved.add(key)) {
      saved.remove(key);
      return false;
    }
    return true;
  }
}

void main() {
  testWidgets('song detail saves and removes favorites with live button state',
      (tester) async {
    final store = _InMemoryFavorites();
    const song = TrackInfo(
      id: 'bz:youtube_music:favorite-ui-test',
      title: 'Favorite UI QA Song',
      artist: 'Breezze QA',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [favoritesStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: bzLightTheme(),
          home: const TrackDetailScreen(track: song),
        ),
      ),
    );
    Future<void> expectVisibleAction(String label) async {
      // Riverpod family invalidation resolves asynchronously after the
      // persistence future. Wait for its next frame without depending on
      // unrelated catalog discovery requests to settle.
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text(label).evaluate().isNotEmpty) return;
      }
      expect(find.text(label), findsOneWidget);
    }

    await expectVisibleAction('Add to Library');
    await tester.ensureVisible(find.text('Add to Library'));
    await tester.tap(find.text('Add to Library'));
    await expectVisibleAction('Remove from Library');
    expect(await store.isFavorite(song.id), isTrue);

    await tester.tap(find.text('Remove from Library'));
    await expectVisibleAction('Add to Library');
    expect(await store.isFavorite(song.id), isFalse);
  });

  testWidgets('YouTube song details offer official visible video playback', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: bzLightTheme(),
          home: const TrackDetailScreen(
            track: TrackInfo(
              id: 'bz:youtube_music:dQw4w9WgXcQ',
              title: 'Available song',
              artist: 'Artist',
            ),
          ),
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Watch on YouTube'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('saved artist stays accessible when Spotify profile cannot be loaded',
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
    expect(find.text('Sign in to view this Spotify artist profile.'), findsOneWidget);
    expect(find.text('Deezer catalog discography'), findsNothing);
    expect(find.text('Concert data provided by JamBase'), findsNothing);
  });

  testWidgets('track detail shows song metadata without inventing an album',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // This is a catalog-metadata test, not a device SQLite test.
        overrides: [favoritesStoreProvider.overrideWithValue(_InMemoryFavorites())],
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
    // The action now correctly shows "Checking Library..." until its
    // owner-scoped saved-state lookup resolves. Await the enabled label.
    for (var i = 0;
        i < 25 && find.text('Add to Library').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
