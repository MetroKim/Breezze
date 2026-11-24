import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/core/database/database_providers.dart';
import 'package:breezze/core/database/outbox_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:breezze/core/database/breezze_database.dart';
import 'package:breezze/core/database/favorites_dao.dart';
import 'package:breezze/core/database/recently_played_dao.dart';
import 'package:breezze/core/database/sync_outbox_dao.dart';

class _ControlledFavoritesApi extends BreezzeApi {
  _ControlledFavoritesApi() : super(baseUrl: 'https://api.breezze.test') {
    accessToken = 'session-a';
  }

  final beganAdd = Completer<void>();
  final resumeAdd = Completer<void>();
  final cloud = <String>{};
  var _firstAdd = true;

  @override
  Future<Map<String, dynamic>> addFavorite(String trackId) async {
    if (_firstAdd) {
      _firstAdd = false;
      beganAdd.complete();
      await resumeAdd.future;
    }
    cloud.add(trackId);
    return {'trackId': trackId};
  }

  @override
  Future<void> removeFavorite(String trackId) async {
    cloud.remove(trackId);
  }
}

class _TestAuth extends AuthSessionController {
  _TestAuth(this.testApi);
  final BreezzeApi testApi;

  @override
  BreezzeApi get api => testApi;

  @override
  AuthState build() =>
      const AuthSignedIn(userId: 'user-a', email: 'a@example.com');

  void switchTo(String ownerId) {
    state = AuthSignedIn(userId: ownerId, email: '$ownerId@example.com');
  }
}

void main() {
  late BreezzeDatabase db;
  late FavoritesDao favorites;
  late RecentlyPlayedDao recent;
  late SyncOutboxDao outbox;

  setUp(() {
    db = BreezzeDatabase(NativeDatabase.memory());
    favorites = FavoritesDao(db);
    recent = RecentlyPlayedDao(db);
    outbox = SyncOutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('favorites with the same track ID remain isolated by account', () async {
    await favorites.add(
      id: 'track-1',
      title: 'A copy',
      artist: 'Artist A',
      ownerId: 'user-a',
    );
    await favorites.add(
      id: 'track-1',
      title: 'B copy',
      artist: 'Artist B',
      ownerId: 'user-b',
    );

    expect((await favorites.list(ownerId: 'user-a')).single.title.value, 'A copy');
    expect((await favorites.list(ownerId: 'user-b')).single.title.value, 'B copy');
    expect(await favorites.list(ownerId: 'guest'), isEmpty);
    expect(await favorites.contains('track-1', ownerId: 'user-a'), isTrue);
    expect(await favorites.contains('track-1', ownerId: 'user-b'), isTrue);

    await favorites.remove('track-1', ownerId: 'user-a');

    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
    expect((await favorites.list(ownerId: 'user-b')).single.title.value, 'B copy');
  });

  test('recent listening history is isolated and capped per account', () async {
    await recent.record(
      id: 'same-track',
      title: 'A recent track',
      artist: 'Artist A',
      ownerId: 'user-a',
    );
    await recent.record(
      id: 'same-track',
      title: 'B recent track',
      artist: 'Artist B',
      ownerId: 'user-b',
    );

    expect((await recent.list(ownerId: 'user-a')).single.title.value, 'A recent track');
    expect((await recent.list(ownerId: 'user-b')).single.title.value, 'B recent track');
    expect(await recent.list(ownerId: 'guest'), isEmpty);
  });

  test('pending sync operations are returned only for their owner', () async {
    await favorites.add(
      id: 'track-1',
      title: 'Song',
      artist: 'Artist',
      ownerId: 'user-a',
    );
    await recent.record(
      id: 'track-2',
      title: 'Another song',
      artist: 'Artist',
      ownerId: 'user-b',
    );

    final userAOps = await outbox.pending(ownerId: 'user-a');
    final userBOps = await outbox.pending(ownerId: 'user-b');

    expect(userAOps.map((op) => op.trackId), ['user-a::track-1']);
    expect(userBOps.map((op) => op.trackId), ['user-b::track-2']);
  });

  test('offline remove keeps an ordered cloud compensation after pending add',
      () async {
    await favorites.add(
      id: 'new-track',
      title: 'New song',
      artist: 'Artist',
      ownerId: 'user-a',
    );

    await favorites.remove('new-track', ownerId: 'user-a');

    expect((await outbox.pending(ownerId: 'user-a'))
        .map((op) => op.op).toList(),
      ['favorite.add', 'favorite.remove']);
    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
    expect(await favorites.reconcileCloud(
      ownerId: 'user-a',
      tracks: const [],
    ), isFalse);
  });

  test('removal during an in-flight add is drained before returning', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    final api = _ControlledFavoritesApi();
    final container = ProviderContainer(overrides: [
      authSessionProvider.overrideWith(() => _TestAuth(api)),
      breezzeDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await favorites.add(
      id: id, title: 'A song', artist: 'An artist', ownerId: 'user-a',
    );
    final syncing = container.read(outboxSyncProvider).drainIfSignedIn();
    await api.beganAdd.future.timeout(const Duration(seconds: 15));
    await favorites.remove(id, ownerId: 'user-a');
    api.resumeAdd.complete();
    await syncing;

    expect(api.cloud, isEmpty);
    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
    expect(await outbox.pending(ownerId: 'user-a'), isEmpty);
  });

  test('a token rotation during network add never acknowledges old outbox',
      () async {
    const id = '22222222-2222-4222-8222-222222222222';
    final api = _ControlledFavoritesApi();
    final container = ProviderContainer(overrides: [
      authSessionProvider.overrideWith(() => _TestAuth(api)),
      breezzeDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await favorites.add(
      id: id, title: 'A song', artist: 'An artist', ownerId: 'user-a',
    );
    final service = container.read(outboxSyncProvider);
    final syncing = service.drainIfSignedIn();
    await api.beganAdd.future.timeout(const Duration(seconds: 15));
    api.accessToken = 'session-rotated';
    api.resumeAdd.complete();
    await syncing;

    expect((await outbox.pending(ownerId: 'user-a')).single.op,
        'favorite.add');
    await service.drainIfSignedIn(); // idempotent replay on new session
    expect(api.cloud, {id});
    expect(await outbox.pending(ownerId: 'user-a'), isEmpty);
  });

  test('a switch to another account cannot acknowledge old account operations',
      () async {
    const id = '33333333-3333-4333-8333-333333333333';
    final api = _ControlledFavoritesApi();
    final container = ProviderContainer(overrides: [
      authSessionProvider.overrideWith(() => _TestAuth(api)),
      breezzeDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await favorites.add(
      id: id, title: 'A song', artist: 'An artist', ownerId: 'user-a',
    );
    final service = container.read(outboxSyncProvider);
    final syncing = service.drainIfSignedIn();
    await api.beganAdd.future.timeout(const Duration(seconds: 15));
    final auth = container.read(authSessionProvider.notifier) as _TestAuth;
    auth.switchTo('user-b');
    api.resumeAdd.complete();
    await syncing;

    expect((await outbox.pending(ownerId: 'user-a')).single.op,
        'favorite.add');
    expect(await outbox.pending(ownerId: 'user-b'), isEmpty);
    auth.switchTo('user-a');
    await service.drainIfSignedIn();
    expect(await outbox.pending(ownerId: 'user-a'), isEmpty);
  });

  test('guest favorite changes do not accumulate cloud outbox entries', () async {
    await favorites.add(
      id: 'guest-track', title: 'Guest song', artist: 'Guest',
    );
    await favorites.remove('guest-track');
    expect(await outbox.pending(ownerId: 'guest'), isEmpty);
    final all = await db.select(db.syncOutbox).get();
    expect(all, isEmpty);
  });

  test('legacy unscoped rows remain visible only in the guest namespace', () async {
    await favorites.add(
      id: 'legacy-track',
      title: 'Legacy song',
      artist: 'Artist',
    );

    expect((await favorites.list(ownerId: 'guest')).single.id.value, 'legacy-track');
    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
  });
}
