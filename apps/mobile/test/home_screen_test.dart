import 'dart:async';

import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/app/recent_store.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/home/home_screen.dart';
import 'package:breezze/app/main_tab.dart';
import 'package:breezze/features/search/search_screen.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _HomeFavorites extends FavoritesStore {
  _HomeFavorites({this.fail = false});

  bool fail;

  @override
  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    if (fail) throw StateError('disk unavailable');
    return [];
  }
}

class _HomeApi extends BreezzeApi {
  _HomeApi() : super(baseUrl: 'https://api.example.test');

  @override
  Future<List<Map<String, dynamic>>> homeFeed() async => [];

  @override
  Future<Map<String, dynamic>> replaySummary() async => {'totalPlays': 0};
}

class _HomeSession extends AuthSessionController {
  final _testApi = _HomeApi();

  @override
  AuthState build() => const AuthSignedIn(
        userId: 'user-a',
        email: 'a@example.test',
      );

  @override
  BreezzeApi get api => _testApi;

  void switchTo(String userId) {
    state = AuthSignedIn(userId: userId, email: '$userId@example.test');
  }
}

class _GuestHomeSession extends AuthSessionController {
  @override
  AuthState build() => const AuthSignedOut();
}

Future<void> _renderHome(
  WidgetTester tester, {
  required Future<List<RecentEntry>> Function(String ownerId) loadRecent,
  required FavoritesStore favorites,
  bool guest = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      favoritesStoreProvider.overrideWithValue(favorites),
      authSessionProvider.overrideWith(
        guest ? _GuestHomeSession.new : _HomeSession.new,
      ),
    ],
    child: MaterialApp(
      theme: bzLightTheme(),
      home: Scaffold(
        body: HomeScreen(loadRecent: loadRecent),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('Home switches accounts without leaking a delayed previous-owner history',
      (tester) async {
    final oldRequest = Completer<List<RecentEntry>>();
    final queriedOwners = <String>[];

    Future<List<RecentEntry>> history(String ownerId) {
      queriedOwners.add(ownerId);
      if (ownerId == 'user-a') return oldRequest.future;
      if (ownerId == 'user-b') {
        return Future.value(const [
          RecentEntry(id: 'track-b', title: 'Only user B song', artist: 'B'),
        ]);
      }
      return Future.value([]);
    }

    await _renderHome(
      tester,
      loadRecent: history,
      favorites: _HomeFavorites(),
    );
    expect(queriedOwners, ['user-a']);

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    (container.read(authSessionProvider.notifier) as _HomeSession)
        .switchTo('user-b');
    await tester.pump();
    await tester.pump();

    expect(queriedOwners, ['user-a', 'user-b']);
    expect(find.text('Only user B song'), findsWidgets);

    oldRequest.complete(const [
      RecentEntry(id: 'track-a', title: 'Private user A song', artist: 'A'),
    ]);
    await tester.pump();
    expect(find.text('Private user A song'), findsNothing);
    expect(find.text('Only user B song'), findsWidgets);
  });

  testWidgets('Home shows a recoverable error instead of inventing an empty library',
      (tester) async {
    var historyUnavailable = true;
    final favorites = _HomeFavorites(fail: true);
    await _renderHome(
      tester,
      guest: true,
      loadRecent: (_) => historyUnavailable
          ? Future.error(StateError('disk unavailable'))
          : Future.value(<RecentEntry>[]),
      favorites: favorites,
    );
    await tester.pump();

    expect(find.text('Could not load your saved music'), findsOneWidget);
    expect(find.textContaining('Your library has not been erased'), findsOneWidget);
    expect(find.text('Find your first song'), findsNothing);

    historyUnavailable = false;
    favorites.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not load your saved music'), findsNothing);
    expect(find.text('Find your first song'), findsOneWidget);
    expect(find.byType(BzSkeletonTrackRow), findsNothing);
  });

  testWidgets('Home New releases tile selects the real New tab',
      (tester) async {
    await _renderHome(
      tester,
      guest: true,
      loadRecent: (_) async => <RecentEntry>[],
      favorites: _HomeFavorites(),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    await tester.tap(find.text('New releases'));
    expect(container.read(homeTabHintProvider), MainTab.browse.index);
  });

  testWidgets('Home Music videos opens actual Search in official video mode',
      (tester) async {
    await _renderHome(
      tester,
      guest: true,
      loadRecent: (_) async => <RecentEntry>[],
      favorites: _HomeFavorites(),
    );
    await tester.pump();

    await tester.tap(find.text('Music videos'));
    await tester.pump();
    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialVideoSearch, isTrue);
    expect(search.initialQuery, contains('official music video'));
  });
}
