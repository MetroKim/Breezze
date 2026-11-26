import 'dart:async';

import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/features/search/search_screen.dart';
import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SearchSource implements ProviderAdapter {
  final calls = <String>[];
  final pending = <String, Completer<ProviderOp<List<ProviderTrack>>>>{};

  @override
  String get providerId => 'test';

  @override
  String get adapterVersion => '1';

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) {
    calls.add(query);
    final result = Completer<ProviderOp<List<ProviderTrack>>>();
    pending[query] = result;
    return result.future;
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async =>
      ProviderUnsupported('Not used by this test');
}

ProviderOp<List<ProviderTrack>> _result(String title) => ProviderOk([
      ProviderTrack(
        breezzeTrackId: 'bz:youtube_music:abcdefghijk',
        providerTrackId: 'abcdefghijk',
        title: title,
        artist: 'Artist',
        duration: const Duration(minutes: 3),
      ),
    ]);

class _FavoriteMemoryStore extends FavoritesStore {
  final byOwner = <String, Set<String>>{};
  Completer<void>? pendingLookup;
  int writes = 0;

  @override
  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) async {
    if (pendingLookup case final pending?) await pending.future;
    return byOwner[ownerId]?.contains(id) ?? false;
  }

  @override
  Future<bool> toggle(FavoriteTrack track, {String ownerId = 'guest'}) async {
    writes++;
    final saved = byOwner.putIfAbsent(ownerId, () => {});
    if (saved.add(track.id)) return true;
    saved.remove(track.id);
    return false;
  }
}

class _SearchSignedInSession extends AuthSessionController {
  @override
  AuthState build() =>
      const AuthSignedIn(userId: 'search-user-a', email: 'a@example.test');

  void switchTo(String owner) {
    state = AuthSignedIn(userId: owner, email: '$owner@example.test');
  }
}

class _VideoDiscoveryApi extends BreezzeApi {
  _VideoDiscoveryApi() : super(baseUrl: 'https://breezze.example.test');

  @override
  Future<Map<String, dynamic>> searchOfficialYouTubeVideos(
    String query, {int limit = 20}
  ) async => {'kind': 'ok', 'value': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> discoveryMusicVideos({
    String query = 'official music video',
  }) async => {
        'items': query == 'no video match'
            ? <Map<String, dynamic>>[]
            : <Map<String, dynamic>>[
                {
                  'id': 'abcdefghijk',
                  'title': 'Official Video QA',
                  'artist': 'Breezze QA',
                  'durationSec': 180,
                },
              ],
      };
}

class _VideoSearchSession extends AuthSessionController {
  _VideoSearchSession(this.videoApi);

  final BreezzeApi videoApi;

  @override
  AuthState build() => const AuthSignedOut();

  @override
  BreezzeApi get api => videoApi;
}

class _SpotifyArtistSearchApi extends BreezzeApi {
  _SpotifyArtistSearchApi() : super(baseUrl: 'https://breezze.example.test');

  @override
  Future<Map<String, dynamic>> searchSpotifyArtists(String query) async => {
    'kind': 'ok',
    'value': [
      {
        'id': '0TnOYISbd1XYRBk9myaseg',
        'name': 'Test Singer',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> spotifyArtistPage(String id) async => {
    'kind': 'ok',
    'value': {
      'artist': {
        'id': id, 'name': 'Test Singer',
        'url': 'https://open.spotify.com/artist/$id',
        'genres': <String>[],
      },
      'songs': <Object>[], 'albums': <Object>[],
      'newReleases': <Object>[], 'searchSuggestions': <Object>[],
      'songStatus': 'ok', 'albumStatus': 'ok',
      'tours': {'status': 'unsupported', 'events': <Object>[]},
    },
  };
}

class _SpotifySearchSignedIn extends AuthSessionController {
  _SpotifySearchSignedIn(this.source);
  final BreezzeApi source;

  @override
  AuthState build() => const AuthSignedIn(
    userId: 'spotify-artist-search-qa', email: 'search@breezze.example',
  );

  @override
  BreezzeApi get api => source;
}

void main() {
  testWidgets('typeahead debounces and discards older results', (tester) async {
    final source = _SearchSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogSourceProvider.overrideWithValue(source)],
      child: MaterialApp(theme: bzLightTheme(), home: const Scaffold(body: SearchScreen())),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 499));
    expect(source.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.calls, ['old']);

    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.calls, ['old', 'new']);
    source.pending['old']!.complete(_result('Old result'));
    await tester.pump();
    expect(find.text('Old result'), findsNothing);
    source.pending['new']!.complete(_result('New result'));
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);
  });
  testWidgets('Search save action refreshes Library without toggling an existing favorite',
      (tester) async {
    final source = _SearchSource();
    final favorites = _FavoriteMemoryStore();
    final container = ProviderContainer(overrides: [
      catalogSourceProvider.overrideWithValue(source),
      favoritesStoreProvider.overrideWithValue(favorites),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'breezze qa');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['breezze qa']!.complete(_result('Save from Search'));
    await tester.pump();
    expect(find.text('Save from Search'), findsOneWidget);

    Future<void> selectSave() async {
      await tester.ensureVisible(find.byTooltip('Song actions'));
      await tester.tap(find.byTooltip('Song actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to Library').last);
      await tester.pumpAndSettle();
    }

    expect(container.read(favoritesRefreshProvider), 0);
    await selectSave();
    expect(favorites.byOwner['guest'], {'bz:youtube_music:abcdefghijk'});
    expect(favorites.writes, 1);
    expect(container.read(favoritesRefreshProvider), 1);
    expect(find.text('Saved to Library on this device'), findsOneWidget);

    await selectSave();
    expect(favorites.writes, 1);
    expect(container.read(favoritesRefreshProvider), 2);
    // ScaffoldMessenger queues consecutive snackbars. The first successful
    // save remains visible for its standard duration before the second
    // idempotent-save confirmation is presented.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Already in Library'), findsOneWidget);
  });

  testWidgets('Search never saves to the previous owner after account switch',
      (tester) async {
    final source = _SearchSource();
    final favorites = _FavoriteMemoryStore();
    final gate = Completer<void>();
    favorites.pendingLookup = gate;
    final container = ProviderContainer(overrides: [
      catalogSourceProvider.overrideWithValue(source),
      favoritesStoreProvider.overrideWithValue(favorites),
      authSessionProvider.overrideWith(_SearchSignedInSession.new),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'account switch');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['account switch']!.complete(_result('Owner A Result'));
    await tester.pump();
    expect(find.text('Owner A Result'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Song actions'));
    await tester.tap(find.byTooltip('Song actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Library').last);
    await tester.pump();
    (container.read(authSessionProvider.notifier) as _SearchSignedInSession)
        .switchTo('search-user-b');
    await tester.pump();
    gate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(favorites.writes, 0);
    expect(favorites.byOwner, isEmpty);
    expect(container.read(favoritesRefreshProvider), 0);
  });



  testWidgets('Search network errors offer a retry that recovers catalog results',
      (tester) async {
    final source = _SearchSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'retry example');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['retry example']!
        .complete(ProviderError('temporary_provider_failure'));
    await tester.pump();
    expect(
      find.text('Music catalog search is temporarily unavailable. Try again in Breezze.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(source.calls, ['retry example', 'retry example']);
    source.pending['retry example']!.complete(_result('Recovered song'));
    await tester.pump();
    expect(find.text('Recovered song'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });


  testWidgets('source filters appear only after the first search result and Local does not call network',
      (tester) async {
    final source = _SearchSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));
    expect(find.widgetWithText(BzFilterPill, 'Audio'), findsNothing);
    expect(find.widgetWithText(BzFilterPill, 'Video'), findsNothing);
    expect(find.widgetWithText(BzFilterPill, 'Library'), findsNothing);
    expect(find.widgetWithText(BzFilterPill, 'Local'), findsNothing);
    await tester.enterText(find.byType(TextField), 'first query');
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.calls, ['first query']);
    expect(find.widgetWithText(BzFilterPill, 'Audio'), findsNothing);
    source.pending['first query']!.complete(_result('First matching song'));
    await tester.pump();
    for (final scope in ['Audio', 'Video', 'Library', 'Local']) {
      expect(find.widgetWithText(BzFilterPill, scope), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(BzFilterPill, 'Local'));
    await tester.pump();
    expect(find.text('Choose audio files'), findsOneWidget);
    expect(find.textContaining('No matching local songs'), findsOneWidget);
    expect(source.calls, ['first query'],
        reason: 'Local mode must not invoke a remote catalogue');
    await tester.enterText(find.byType(TextField), 'different query');
    // Local is a persistent on-device scope: editing its query keeps the
    // scope selector visible without starting a remote provider search.
    expect(find.widgetWithText(BzFilterPill, 'Audio'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.widgetWithText(BzFilterPill, 'Local'), findsOneWidget);
    expect(source.calls, ['first query'],
        reason: 'Local typeahead must not contact Spotify/Deezer');
  });

  testWidgets('Audio renders a single list, not Spotify and Deezer source shelves',
      (tester) async {
    final source = _SearchSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'bongo');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['bongo']!.complete(ProviderOk([
      ProviderTrack(
        breezzeTrackId: 'bz:spotify:4iV5W9uYEdYUVa79Axb7Rh',
        providerTrackId: 'spotify:4iV5W9uYEdYUVa79Axb7Rh',
        title: 'First Bongo Song',
        artist: 'Artist A',
        duration: const Duration(seconds: 210),
      ),
      ProviderTrack(
        breezzeTrackId: 'bz:deezer:3135556',
        providerTrackId: 'deezer:3135556',
        title: 'Second Bongo Song',
        artist: 'Artist B',
        duration: const Duration(seconds: 240),
      ),
    ]));
    await tester.pump();
    expect(find.text('First Bongo Song'), findsOneWidget);
    expect(find.text('Second Bongo Song'), findsOneWidget);
    expect(find.text('Spotify'), findsNothing,
        reason: 'No standalone provider shelf heading');
    expect(find.text('Deezer'), findsNothing,
        reason: 'No standalone provider shelf heading');
    for (final scope in ['Audio', 'Video', 'Library', 'Local']) {
      expect(find.widgetWithText(BzFilterPill, scope), findsOneWidget);
    }
  });

  testWidgets('Spotify artist result appears before songs and opens the artist page',
      (tester) async {
    final source = _SearchSource();
    final artistApi = _SpotifyArtistSearchApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogSourceProvider.overrideWithValue(source),
        authSessionProvider.overrideWith(() => _SpotifySearchSignedIn(artistApi)),
      ],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Test Singer');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['Test Singer']!.complete(ProviderOk([
      ProviderTrack(
        breezzeTrackId: 'bz:spotify:4iV5W9uYEdYUVa79Axb7Rh',
        providerTrackId: 'spotify:4iV5W9uYEdYUVa79Axb7Rh',
        title: 'Test Singer Song',
        artist: 'Test Singer',
        duration: const Duration(seconds: 180),
      ),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Test Singer'), findsOneWidget);
    expect(find.text('Test Singer Song'), findsOneWidget);
    final list = find.byType(ListTile);
    expect(list, findsWidgets);
    final artistRow = find.ancestor(
      of: find.text('Test Singer'), matching: find.byType(ListTile),
    );
    expect(artistRow, findsOneWidget);
    await tester.tap(artistRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Test Singer'), findsWidgets);
    expect(find.text('Popular Songs'), findsOneWidget);
  });

  testWidgets('Music Videos filter renders external video action and honest empty state',
      (tester) async {
    final api = _VideoDiscoveryApi();
    final source = _SearchSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => _VideoSearchSession(api)),
        catalogSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ));
    expect(find.widgetWithText(BzFilterPill, 'Video'), findsNothing);
    await tester.enterText(find.byType(TextField), 'official qa');
    await tester.pump(const Duration(milliseconds: 500));
    source.pending['official qa']!.complete(_result('Initial audio result'));
    await tester.pump();
    expect(find.widgetWithText(BzFilterPill, 'Video'), findsOneWidget);
    await tester.tap(find.widgetWithText(BzFilterPill, 'Video'));
    await tester.pump();
    expect(find.text('Official Video QA'), findsOneWidget);
    expect(find.byTooltip('Watch music video'), findsOneWidget);
    expect(find.byTooltip('Song actions'), findsNothing);

    await tester.enterText(find.byType(TextField), 'no video match');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      find.text('No official videos found for "no video match"'),
      findsOneWidget,
    );
    expect(find.byTooltip('Watch music video'), findsNothing);
  });

}
