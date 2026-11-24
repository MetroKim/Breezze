import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/database/breezze_database.dart';
import '../../../lib/core/database/favorites_dao.dart';
import '../../../lib/core/database/catalog_id_map_dao.dart';
import '../../../lib/core/database/sync_outbox_dao.dart';

void main() {
  late BreezzeDatabase db;
  late FavoritesDao favorites;
  late SyncOutboxDao outbox;

  setUp(() {
    db = BreezzeDatabase(NativeDatabase.memory());
    favorites = FavoritesDao(db);
    outbox = SyncOutboxDao(db);
  });

  tearDown(() async => db.close());

  const cloudSong = (
    id: '11111111-1111-4111-8111-111111111111',
    title: 'Synced song',
    artist: 'Catalog artist',
    artworkUrl: null as String?,
    durationMs: 180000,
  );

  test('pending offline additions cannot be erased by a cloud snapshot', () async {
    await favorites.add(
      id: 'bz:jamendo:track-1',
      title: 'Saved offline',
      artist: 'Offline artist',
      ownerId: 'user-a',
    );
    final accepted = await favorites.reconcileCloud(
      ownerId: 'user-a',
      tracks: [cloudSong],
    );
    expect(accepted, isFalse);
    expect((await favorites.list(ownerId: 'user-a')).single.id.value,
      'bz:jamendo:track-1');
    expect(await outbox.pending(ownerId: 'user-a'), hasLength(1));
  });

  test('cloud hydration replaces only the correct owner without new uploads', () async {
    await favorites.add(
      id: 'locally-saved',
      title: 'Old item',
      artist: 'Old artist',
      ownerId: 'user-a',
    );
    await favorites.add(
      id: 'other-user-track',
      title: 'Private track',
      artist: 'Other artist',
      ownerId: 'user-b',
    );
    for (final pending in await outbox.pending(ownerId: 'user-a')) {
      await outbox.remove(pending.id);
    }

    expect(await favorites.reconcileCloud(ownerId: 'user-a',
      tracks: [cloudSong]), isTrue);
    final own = await favorites.list(ownerId: 'user-a');
    expect(own, hasLength(1));
    expect(own.single.id.value, cloudSong.id);
    expect(own.single.title.value, cloudSong.title);
    expect((await favorites.list(ownerId: 'user-b')).single.id.value,
      'other-user-track');
    expect(await outbox.pending(ownerId: 'user-a'), isEmpty);

    expect(await favorites.reconcileCloud(ownerId: 'guest',
      tracks: [cloudSong]), isFalse);
    expect(await favorites.reconcileCloud(ownerId: 'user-a',
      tracks: []), isTrue);
    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
    expect(await favorites.list(ownerId: 'user-b'), hasLength(1));
  });

  test('unrelated recent-play outbox work does not block favorite downloads', () async {
    await db.into(db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        op: 'recent.play',
        trackId: 'user-a::some-recent-track',
      ),
    );
    expect(await favorites.reconcileCloud(
      ownerId: 'user-a',
      tracks: [cloudSong],
    ), isTrue);
    expect((await favorites.list(ownerId: 'user-a')).single.id.value,
      cloudSong.id);
    expect(await outbox.pending(ownerId: 'user-a'), hasLength(1));
  });

  test('cloud uses known external IDs and supports canonical removal', () async {
    const externalId = 'bz:jamendo:track-1';
    await favorites.add(
      id: externalId,
      title: 'Original title',
      artist: 'Original artist',
      ownerId: 'user-a',
    );
    for (final pending in await outbox.pending(ownerId: 'user-a')) {
      await outbox.remove(pending.id);
    }
    await CatalogIdMapDao(db).save(externalId, cloudSong.id);

    expect(await favorites.reconcileCloud(ownerId: 'user-a',
      tracks: [cloudSong]), isTrue);
    expect((await favorites.list(ownerId: 'user-a')).single.id.value,
      externalId);
    expect(await favorites.contains(externalId, ownerId: 'user-a'), isTrue);

    await favorites.remove(externalId, ownerId: 'user-a');
    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
    expect((await outbox.pending(ownerId: 'user-a')).single.op,
      'favorite.remove');

    // A separate device may have stored only the canonical ID.
    for (final pending in await outbox.pending(ownerId: 'user-a')) {
      await outbox.remove(pending.id);
    }
    expect(await favorites.reconcileCloud(ownerId: 'user-a',
      tracks: [cloudSong]), isTrue);
    expect(await favorites.contains(externalId, ownerId: 'user-a'), isTrue);
    await favorites.remove(externalId, ownerId: 'user-a');
    expect(await favorites.list(ownerId: 'user-a'), isEmpty);
  });
}
