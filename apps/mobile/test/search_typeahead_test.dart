import 'dart:async';

import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/core/auth/auth_session.dart';
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


}
