import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/app/saved_album_store.dart';
import 'package:breezze/core/api/breezze_api.dart';

class _MemoryStore implements SavedAlbumKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _FakeCloud extends BreezzeApi {
  _FakeCloud() : super(baseUrl: 'https://breezze.example.test') {
    accessToken = 'token-a';
  }

  final albums = <String, Map<String, dynamic>>{};
  int upserts = 0;
  int removals = 0;
  bool failNextUpsert = false;
  bool failNextList = false;
  void Function()? onUpsert;

  @override
  Future<Map<String, dynamic>> upsertSavedAlbum({
    required String externalAlbumId,
    required String title,
    required String artist,
    String? artworkUrl,
    String? catalogUrl,
    List<String> genres = const [],
    bool isCompilation = false,
  }) async {
    upserts++;
    if (failNextUpsert) {
      failNextUpsert = false;
      throw Exception('Offline');
    }
    albums[externalAlbumId] = {
      'source': 'apple_itunes',
      'externalAlbumId': externalAlbumId,
      'title': title,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'catalogUrl': catalogUrl,
      'genres': genres,
      'isCompilation': isCompilation,
      'savedAt': DateTime.utc(2026).toIso8601String(),
    };
    onUpsert?.call();
    return {'saved': true};
  }

  @override
  Future<void> deleteSavedAlbum(String externalAlbumId) async {
    removals++;
    albums.remove(externalAlbumId);
  }

  @override
  Future<Map<String, dynamic>> getSavedAlbums({String? cursor}) async {
    if (failNextList) {
      failNextList = false;
      throw Exception('Network unavailable during cloud read');
    }
    if (cursor != null) throw StateError('Unexpected page');
    return {
      'items': albums.values.toList(),
      'nextCursor': null,
    };
  }
}

SavedAlbum _album(String id) => SavedAlbum(
  id: id,
  title: 'Album $id',
  artist: 'Artist',
  genres: const ['Afrobeats'],
  isCompilation: true,
  addedAt: DateTime.utc(2026),
);

void main() {
  const owner = 'user-a';

  test('save uploads to account cloud and reconciles local cache', () async {
    final memory = _MemoryStore();
    final store = SavedAlbumStore(keyValueStore: memory);
    final api = _FakeCloud();
    await store.save(owner, _album('123'));
    await store.syncWithCloud(owner, api, ownerStillActive: () => true);

    expect(api.upserts, 1);
    expect(api.albums.keys, contains('123'));
    final albums = await store.load(owner);
    expect(albums.single.id, '123');
    expect(albums.single.genres, ['Afrobeats']);
    expect(albums.single.isCompilation, isTrue);
    expect(
      jsonDecode(memory.values['breezze:saved_albums:pending:v1:$owner']!),
      isEmpty,
    );
  });

  test('offline upsert survives restart and replays exactly once', () async {
    final memory = _MemoryStore();
    final api = _FakeCloud()..failNextUpsert = true;
    final first = SavedAlbumStore(keyValueStore: memory);
    await first.save(owner, _album('456'));

    await expectLater(
      first.syncWithCloud(owner, api, ownerStillActive: () => true),
      throwsException,
    );
    expect((await first.load(owner)).single.id, '456');

    final restored = SavedAlbumStore(keyValueStore: memory);
    await restored.syncWithCloud(owner, api, ownerStillActive: () => true);
    expect(api.albums.keys, contains('456'));
    expect((await restored.load(owner)).single.id, '456');
    expect(api.upserts, 2); // 1 failed, 1 acknowledged
  });

  test('cloud read failure does not wipe an existing local album', () async {
    final memory = _MemoryStore();
    final api = _FakeCloud();
    final store = SavedAlbumStore(keyValueStore: memory);
    await store.save(owner, _album('111'));
    api.failNextList = true;
    await expectLater(
      store.syncWithCloud(owner, api, ownerStillActive: () => true),
      throwsException,
    );
    expect((await store.load(owner)).single.id, '111');

    await store.syncWithCloud(owner, api, ownerStillActive: () => true);
    expect((await store.load(owner)).single.id, '111');
  });

  test('pending removal stays deleted locally and reaches cloud', () async {
    final memory = _MemoryStore();
    final api = _FakeCloud();
    final store = SavedAlbumStore(keyValueStore: memory);
    await store.save(owner, _album('789'));
    await store.syncWithCloud(owner, api, ownerStillActive: () => true);
    await store.remove(owner, '789');
    expect(await store.load(owner), isEmpty);

    await store.syncWithCloud(owner, api, ownerStillActive: () => true);
    expect(api.removals, 1);
    expect(api.albums, isEmpty);
    expect(await store.load(owner), isEmpty);
  });

  test('switching user or token aborts before another API operation', () async {
    final memory = _MemoryStore();
    final api = _FakeCloud();
    final store = SavedAlbumStore(keyValueStore: memory);
    await store.save(owner, _album('123'));
    await store.save(owner, _album('234'));
    api.onUpsert = () { api.accessToken = 'token-b'; };

    await expectLater(
      store.syncWithCloud(owner, api, ownerStillActive: () => true),
      throwsStateError,
    );
    expect(api.upserts, 1);
    expect((await store.load(owner)).length, 2);
    // An owner-check failure also prevents *any* network request.
    final otherApi = _FakeCloud();
    await expectLater(
      store.syncWithCloud(owner, otherApi,
          ownerStillActive: () => false),
      throwsStateError,
    );
    expect(otherApi.upserts, 0);
  });

  test('one-time local migration does not resurrect remote deletions', () async {
    final memory = _MemoryStore();
    memory.values['breezze:saved_albums:v1:$owner'] =
        jsonEncode([_album('567').toJson()]);
    final api = _FakeCloud();
    final store = SavedAlbumStore(keyValueStore: memory);

    await store.syncWithCloud(owner, api, ownerStillActive: () => true);
    expect(api.albums.keys, contains('567'));

    api.albums.clear(); // Another device removed the saved album.
    await store.syncWithCloud(owner, api, ownerStillActive: () => true);
    expect(api.albums, isEmpty);
    expect(await store.load(owner), isEmpty);
  });

  test('local albums belong to the selected owner only', () async {
    final memory = _MemoryStore();
    final store = SavedAlbumStore(keyValueStore: memory);
    await store.save('user-a', _album('123'));
    await store.save('user-b', _album('999'));
    expect((await store.load('user-a')).single.id, '123');
    expect((await store.load('user-b')).single.id, '999');
  });
}
