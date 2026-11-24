import 'package:breezze/app/followed_artist_store.dart';
import 'package:breezze/app/saved_album_store.dart';
import 'package:breezze/app/bootstrap.dart' show FavoriteTrack, FavoritesStore, favoritesRefreshProvider;
import 'package:breezze/core/database/db_instance.dart';
import 'package:breezze/core/database/sync_outbox_dao.dart';
import 'package:breezze/features/player/player_controller.dart' show TrackInfo;
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/catalog/catalog_detail_screens.dart';
import 'package:breezze/features/search/search_screen.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// Isolated API simulator for native UI acceptance; live API/account
/// isolation is covered by the separate production playlist smoke workflow.
class _ArtistCloud {
  final byOwner = <String, Map<String, Map<String, dynamic>>>{};
  final albumsByOwner = <String, Map<String, Map<String, dynamic>>>{};
}

class _ArtistApi extends BreezzeApi {
  _ArtistApi(this.cloud, this.ownerId)
      : super(baseUrl: 'https://breezze.example.test') {
    accessToken = 'qa-' + ownerId;
  }

  final _ArtistCloud cloud;
  final String ownerId;
  bool offline = false;

  Map<String, Map<String, dynamic>> get records =>
      cloud.byOwner.putIfAbsent(ownerId, () => {});

  Map<String, Map<String, dynamic>> get albums =>
      cloud.albumsByOwner.putIfAbsent(ownerId, () => {});

  void _checkOnline() {
    if (offline) throw StateError('Simulated offline connection');
  }

  @override
  Future<Map<String, dynamic>> searchAllProviders(String query) async {
    _checkOnline();
    return {
      'query': query,
      'providers': [
        {
          'providerId': 'youtube_music',
          'result': {
            'kind': 'ok',
            'value': [
              {
                'providerTrackId': 'abcdefghijk',
                'title': 'Native Search QA Song',
                'artist': 'Breezze QA Artist',
                'durationSec': 180,
              },
            ],
          },
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getFollowedArtists() async {
    _checkOnline();
    return {
      'items': [
        for (final row in records.values) Map<String, dynamic>.from(row),
      ],
    };
  }

  @override
  Future<void> followArtist(
    String key, bool following, {String? displayName}
  ) async {
    _checkOnline();
    if (!following) {
      records.remove(key);
      return;
    }
    final current = records[key];
    records[key] = {
      'artistKey': key,
      'displayName': displayName ?? current?['displayName'] ?? key,
      'isPinned': current?['isPinned'] ?? false,
      'followedAt': current?['followedAt'] ??
          DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<void> pinArtist(String key, bool pinned) async {
    _checkOnline();
    final record = records[key];
    if (record == null) throw StateError('Artist is not followed');
    record['isPinned'] = pinned;
  }

  @override
  Future<Map<String, dynamic>> discoveryAlbumTracks(String albumId) async => {
        'album': {
          'genres': <String>['Afrobeats'],
          'isCompilation': false,
        },
        'items': <Map<String, dynamic>>[],
      };

  @override
  Future<Map<String, dynamic>> getSavedAlbums({String? cursor}) async {
    _checkOnline();
    if (cursor != null) throw StateError('Unexpected album cursor');
    return {
      'items': [
        for (final album in albums.values) Map<String, dynamic>.from(album),
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> upsertSavedAlbum({
    required String externalAlbumId,
    required String title,
    required String artist,
    String? artworkUrl,
    String? catalogUrl,
    List<String> genres = const [],
    bool isCompilation = false,
    bool? isPinned,
  }) async {
    _checkOnline();
    final previous = albums[externalAlbumId];
    albums[externalAlbumId] = {
      'source': 'apple_itunes',
      'externalAlbumId': externalAlbumId,
      'title': title,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'catalogUrl': catalogUrl,
      'genres': genres,
      'isCompilation': isCompilation,
      'isPinned': isPinned ?? previous?['isPinned'] ?? false,
      'savedAt': previous?['savedAt'] ??
          DateTime.now().toUtc().toIso8601String(),
    };
    return {'saved': true};
  }

  @override
  Future<void> deleteSavedAlbum(String externalAlbumId) async {
    _checkOnline();
    albums.remove(externalAlbumId);
  }

  @override
  Future<Map<String, dynamic>> discoveryTrackSearch(String query) async =>
      {'items': <Map<String, dynamic>>[]};

  // Keep the local favorites outbox pending while simulated cloud sync is
  // unavailable; the production HTTP smoke separately tests cloud delivery.
  @override
  Future<Map<String, dynamic>> resolveCatalogTrack({
    required String externalId,
    required String source,
    required String title,
    required String artistName,
    required int durationSec,
  }) async => throw StateError('Native favorites offline fixture');

  @override
  Future<Map<String, dynamic>> discoveryArtistSearch(String query) async =>
      {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> discoveryMusicVideos({
    String query = 'official music video',
  }) async => {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> discoveryConcerts({
    String country = 'TZ',
    String? city,
  }) async => {'items': <Map<String, dynamic>>[]};
}

class _CurrentApi {
  _CurrentApi(this.value);
  _ArtistApi value;
}

class _SignedInArtistSession extends AuthSessionController {
  _SignedInArtistSession(this.currentApi, this.ownerId);

  final _CurrentApi currentApi;
  final String ownerId;

  @override
  AuthState build() => AuthSignedIn(
        userId: ownerId,
        email: ownerId + '@example.test',
      );

  @override
  BreezzeApi get api => currentApi.value;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native artist UI persists offline pins and isolates accounts',
      (tester) async {
    // Per-test owner and artist identifiers prevent cross-test contamination.
    final seed = DateTime.now().microsecondsSinceEpoch.toString();
    final ownerA = 'artist-ui-a-' + seed;
    final ownerB = 'artist-ui-b-' + seed;
    final artistId = 'native_qa_' + seed;
    final artistKey = 'catalog:' + artistId;
    const artistName = 'Breezze Native QA Artist';

    final cloud = _ArtistCloud();
    final apiA = _ArtistApi(cloud, ownerA);
    final secondSession = _ArtistApi(cloud, ownerA);
    final apiB = _ArtistApi(cloud, ownerB);
    final current = _CurrentApi(apiA);
    final storage = const FlutterSecureStorage();

    Future<void> waitForLabel(String label) async {
      for (var attempt = 0; attempt < 80; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text(label).evaluate().isNotEmpty) return;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Artist screen never displayed ' + label);
    }

    Future<void> waitForSyncedOutbox(String ownerId) async {
      for (var attempt = 0; attempt < 80; attempt++) {
        if (await FollowedArtistStore().pendingCount(ownerId) == 0) return;
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Followed artist outbox did not drain');
    }

    Future<void> mountArtist(String ownerId) async {
      // Reconstruct the real artist page and Riverpod scope, but keep
      // Keychain/Keystore-backed persistence between screen instances.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _SignedInArtistSession(current, ownerId),
          ),
        ],
        child: MaterialApp(
          theme: bzLightTheme(),
          home: ArtistDetailScreen(
            artist: artistName,
            canonicalArtistId: artistId,
            savedTracks: const [],
          ),
        ),
      ));
    }

    try {
      await mountArtist(ownerA);
      await waitForLabel('Follow');
      await tester.tap(find.text('Follow'));
      await waitForLabel('Following');
      expect((await FollowedArtistStore().find(ownerA, artistKey))?.isPinned,
          isFalse);

      // The real Pin button queues its change while the API is offline.
      apiA.offline = true;
      await tester.tap(find.text('Pin'));
      await waitForLabel('Unpin');
      expect((await FollowedArtistStore().find(ownerA, artistKey))?.isPinned,
          isTrue);
      expect(await FollowedArtistStore().pendingCount(ownerA), 1);

      // Recreate the entire widget tree: the native device still shows Unpin.
      await mountArtist(ownerA);
      await waitForLabel('Unpin');
      expect((await FollowedArtistStore().find(ownerA, artistKey))?.isPinned,
          isTrue);

      apiA.offline = false;
      await mountArtist(ownerA);
      await waitForLabel('Unpin');
      await waitForSyncedOutbox(ownerA);
      expect((await secondSession.getFollowedArtists())['items'],
          contains(predicate<Map>((row) =>
              row['artistKey'] == artistKey && row['isPinned'] == true)));

      // A different account cannot view or change A's follow/pin state.
      expect((await apiB.getFollowedArtists())['items'], isEmpty);
      current.value = apiB;
      await mountArtist(ownerB);
      await waitForLabel('Follow');
      expect(await FollowedArtistStore().find(ownerB, artistKey), isNull);

      current.value = apiA;
      await mountArtist(ownerA);
      await waitForLabel('Unpin');
      await tester.tap(find.text('Unpin'));
      await waitForLabel('Pin');
      await waitForSyncedOutbox(ownerA);
      expect((cloud.byOwner[ownerA]?[artistKey])?['isPinned'], isFalse);

      await tester.tap(find.text('Following'));
      await waitForLabel('Follow');
      await waitForSyncedOutbox(ownerA);
      expect((await secondSession.getFollowedArtists())['items'], isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // Clear only this test's owner-scoped data, never another account.
      for (final owner in [ownerA, ownerB]) {
        final key = Uri.encodeComponent(owner);
        await storage.delete(key: 'breezze:followed_artists:v1:' + key);
        await storage.delete(
          key: 'breezze:followed_artists:pending:v1:' + key,
        );
      }
    }
  });
  testWidgets('native saved album UI syncs pins, restart and account isolation',
      (tester) async {
    final seed = DateTime.now().microsecondsSinceEpoch.toString();
    final ownerA = 'album-ui-a-' + seed;
    final ownerB = 'album-ui-b-' + seed;
    final albumId = 'native_album_' + seed;
    final cloud = _ArtistCloud();
    final apiA = _ArtistApi(cloud, ownerA);
    final apiB = _ArtistApi(cloud, ownerB);
    final current = _CurrentApi(apiA);
    final storage = const FlutterSecureStorage();

    Future<void> waitForLabel(String label) async {
      for (var attempt = 0; attempt < 80; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text(label).evaluate().isNotEmpty) return;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Album screen never displayed ' + label);
    }

    Future<void> mountAlbum(String ownerId) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _SignedInArtistSession(current, ownerId),
          ),
        ],
        child: MaterialApp(
          theme: bzLightTheme(),
          home: AppleAlbumCatalogScreen(
            albumId: albumId,
            title: 'Breezze Native QA Album',
            artist: 'Breezze QA Artist',
          ),
        ),
      ));
    }

    try {
      await mountAlbum(ownerA);
      await waitForLabel('Add Album to Library');
      await tester.ensureVisible(find.text('Add Album to Library'));
      await tester.tap(find.text('Add Album to Library'));
      await waitForLabel('Saved in Library');
      expect(await SavedAlbumStore().contains(ownerA, albumId), isTrue);
      expect(apiA.albums[albumId]?['genres'], ['Afrobeats']);
      expect(apiA.albums[albumId]?['isPinned'], isFalse);

      // Tap the real saved-album Pin action while offline. The native
      // Keychain / Keystore persists it through a complete page remount.
      apiA.offline = true;
      await waitForLabel('Pin album to top');
      await tester.ensureVisible(find.text('Pin album to top'));
      await tester.tap(find.text('Pin album to top'));
      await waitForLabel('Unpin album');
      expect((await SavedAlbumStore().load(ownerA)).single.isPinned, isTrue);
      await mountAlbum(ownerA);
      await waitForLabel('Saved in Library');
      await waitForLabel('Unpin album');
      expect((await SavedAlbumStore().load(ownerA)).single.isPinned, isTrue);

      // Reconnect and replay the durable pin journal into owner A's cloud.
      apiA.offline = false;
      await SavedAlbumStore().syncWithCloud(
        ownerA, apiA, ownerStillActive: () => true,
      );
      expect(apiA.albums[albumId]?['isPinned'], isTrue);
      expect((await apiB.getSavedAlbums())['items'], isEmpty);

      // Another account cannot observe owner A's saved album or pin.
      current.value = apiB;
      await mountAlbum(ownerB);
      await waitForLabel('Add Album to Library');
      expect(await SavedAlbumStore().contains(ownerB, albumId), isFalse);

      current.value = apiA;
      await mountAlbum(ownerA);
      await waitForLabel('Saved in Library');
      await tester.ensureVisible(find.text('Saved in Library'));
      await tester.tap(find.text('Saved in Library'));
      await waitForLabel('Add Album to Library');
      expect(apiA.albums.containsKey(albumId), isFalse);
      expect(await SavedAlbumStore().contains(ownerA, albumId), isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // The acceptance fixture removes only its own encrypted owner records.
      for (final owner in [ownerA, ownerB]) {
        final suffix = Uri.encodeComponent(owner);
        await storage.delete(key: 'breezze:saved_albums:v1:' + suffix);
        await storage.delete(key: 'breezze:saved_albums:pending:v1:' + suffix);
        await storage.delete(key: 'breezze:saved_albums:cloud_ready:v1:' + suffix);
      }
    }
  });

  testWidgets('native song detail favorites survive app restart and isolate owners',
      (tester) async {
    final seed = DateTime.now().microsecondsSinceEpoch.toString();
    final ownerA = 'favorite-ui-a-' + seed;
    final ownerB = 'favorite-ui-b-' + seed;
    final trackId = 'bz:youtube_music:favorite_native_' + seed;
    final favorite = FavoriteTrack(
      id: trackId,
      title: 'Native Favorites QA Song',
      artist: 'Breezze QA Artist',
    );
    final cloud = _ArtistCloud();
    final apiA = _ArtistApi(cloud, ownerA);
    final apiB = _ArtistApi(cloud, ownerB);
    final current = _CurrentApi(apiA);
    final favorites = FavoritesStore();

    Future<void> waitForLabel(String label) async {
      for (var attempt = 0; attempt < 80; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text(label).evaluate().isNotEmpty) return;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Favorite screen never displayed ' + label);
    }

    Future<void> mountSong(String ownerId) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _SignedInArtistSession(current, ownerId),
          ),
        ],
        child: MaterialApp(
          theme: bzLightTheme(),
          home: TrackDetailScreen(
            track: TrackInfo(
              id: trackId,
              title: favorite.title,
              artist: favorite.artist,
            ),
          ),
        ),
      ));
    }

    try {
      await mountSong(ownerA);
      await waitForLabel('Add to Library');
      await tester.ensureVisible(find.text('Add to Library'));
      await tester.tap(find.text('Add to Library'));
      await waitForLabel('Remove from Library');
      expect(await favorites.isFavorite(trackId, ownerId: ownerA), isTrue);

      // New page and provider scope, same native owner-prefixed SQLite.
      await mountSong(ownerA);
      await waitForLabel('Remove from Library');
      current.value = apiB;
      await mountSong(ownerB);
      await waitForLabel('Add to Library');
      expect(await favorites.isFavorite(trackId, ownerId: ownerB), isFalse);

      current.value = apiA;
      await mountSong(ownerA);
      await waitForLabel('Remove from Library');
      await tester.ensureVisible(find.text('Remove from Library'));
      await tester.tap(find.text('Remove from Library'));
      await waitForLabel('Add to Library');
      expect(await favorites.isFavorite(trackId, ownerId: ownerA), isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // Delete only test-owned local rows/outbox entries; no real account
      // data is involved and neither other owners nor guest are touched.
      for (final owner in [ownerA, ownerB]) {
        if (await favorites.isFavorite(trackId, ownerId: owner)) {
          await favorites.toggle(favorite, ownerId: owner);
        }
        for (final event in await SyncOutboxDao(breezzeDb)
            .pending(ownerId: owner)) {
          await SyncOutboxDao(breezzeDb).discard(event.id);
        }
      }
    }
  });

  testWidgets('native Search menu saves song and isolates account data',
      (tester) async {
    final seed = DateTime.now().microsecondsSinceEpoch.toString();
    final ownerA = 'search-ui-a-' + seed;
    final ownerB = 'search-ui-b-' + seed;
    const trackId = 'bz:youtube_music:abcdefghijk';
    const favorite = FavoriteTrack(
      id: trackId,
      title: 'Native Search QA Song',
      artist: 'Breezze QA Artist',
      durationMs: 180000,
    );
    final cloud = _ArtistCloud();
    final apiA = _ArtistApi(cloud, ownerA);
    final apiB = _ArtistApi(cloud, ownerB);
    final current = _CurrentApi(apiA);
    final favorites = FavoritesStore();

    Future<void> mountSearch(String ownerId) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _SignedInArtistSession(current, ownerId),
          ),
        ],
        child: MaterialApp(
          theme: bzLightTheme(),
          home: const Scaffold(body: SearchScreen()),
        ),
      ));
    }

    Future<void> waitForSearchResult() async {
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('Native Search QA Song').evaluate().isNotEmpty) return;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Native federated search result did not render');
    }

    try {
      await mountSearch(ownerA);
      await tester.enterText(find.byType(TextField).first, 'native search');
      await tester.pump(const Duration(milliseconds: 500));
      await waitForSearchResult();

      await tester.ensureVisible(find.byTooltip('Song actions'));
      await tester.tap(find.byTooltip('Song actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Library').last);

      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        if (await favorites.isFavorite(trackId, ownerId: ownerA)) break;
      }
      expect(await favorites.isFavorite(trackId, ownerId: ownerA), isTrue);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchScreen)),
      );
      expect(container.read(favoritesRefreshProvider), 1);

      // A different signed-in account must not see the previous owner's
      // persisted favorite, even when the search metadata ID is identical.
      current.value = apiB;
      await mountSearch(ownerB);
      expect(await favorites.isFavorite(trackId, ownerId: ownerB), isFalse);
      current.value = apiA;
      await mountSearch(ownerA);
      expect(await favorites.isFavorite(trackId, ownerId: ownerA), isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final owner in [ownerA, ownerB]) {
        if (await favorites.isFavorite(trackId, ownerId: owner)) {
          await favorites.toggle(favorite, ownerId: owner);
        }
        final dao = SyncOutboxDao(breezzeDb);
        for (final event in await dao.pending(ownerId: owner)) {
          await dao.discard(event.id);
        }
      }
    }
  });

}
