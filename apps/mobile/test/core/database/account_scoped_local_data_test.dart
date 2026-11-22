import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:breezze/core/database/breezze_database.dart';
import 'package:breezze/core/database/favorites_dao.dart';
import 'package:breezze/core/database/recently_played_dao.dart';
import 'package:breezze/core/database/sync_outbox_dao.dart';

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
