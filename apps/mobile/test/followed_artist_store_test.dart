import 'package:breezze/app/followed_artist_store.dart';
import 'package:breezze/app/saved_album_store.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements SavedAlbumKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _Cloud {
  final byOwner = <String, Map<String, Map<String, dynamic>>>{};
}

class _FakeArtistApi extends BreezzeApi {
  final _Cloud cloud;
  final String owner;
  bool failNextFollow = false;

  _FakeArtistApi(this.cloud, this.owner)
      : super(baseUrl: 'https://breezze.example.test') {
    accessToken = 'token:' + owner;
  }

  Map<String, Map<String, dynamic>> get rows =>
      cloud.byOwner.putIfAbsent(owner, () => {});

  @override
  Future<void> followArtist(
    String key, bool following, {String? displayName}
  ) async {
    if (failNextFollow) {
      failNextFollow = false;
      throw StateError('Offline');
    }
    if (!following) {
      rows.remove(key);
      return;
    }
    final current = rows[key];
    rows[key] = {
      'artistKey': key,
      'displayName': displayName ?? current?['displayName'],
      'isPinned': current?['isPinned'] ?? false,
      'followedAt':
          current?['followedAt'] ?? DateTime.utc(2026, 1, 1).toIso8601String(),
    };
  }

  @override
  Future<void> pinArtist(String key, bool pinned) async {
    if (!rows.containsKey(key)) throw StateError('Not followed');
    rows[key]!['isPinned'] = pinned;
  }

  @override
  Future<Map<String, dynamic>> getFollowedArtists() async => {
        'items': [
          for (final row in rows.values) Map<String, dynamic>.from(row),
        ],
      };
}

void main() {
  test('offline artist pin survives restart and reaches second device',
      () async {
    final cloud = _Cloud();
    final storageA = _MemoryStore();
    final storageB = _MemoryStore();
    final phoneA = FollowedArtistStore(keyValueStore: storageA);
    final phoneB = FollowedArtistStore(keyValueStore: storageB);
    final apiA = _FakeArtistApi(cloud, 'owner');
    final apiB = _FakeArtistApi(cloud, 'owner');

    await phoneA.follow('owner', 'apple:12', 'Artist One');
    await phoneA.follow('owner', 'apple:13', 'Artist Two');
    expect(await phoneA.setPinned('owner', 'apple:12', true), isTrue);
    expect(await phoneA.setPinned('owner', 'apple:12', true), isFalse);
    expect((await phoneA.load('owner')).first.artistKey, 'apple:12');

    apiA.failNextFollow = true;
    await expectLater(
      phoneA.syncWithCloud('owner', apiA, ownerStillActive: () => true),
      throwsStateError,
    );
    final restarted = FollowedArtistStore(keyValueStore: storageA);
    expect((await restarted.find('owner', 'apple:12'))?.isPinned, true);
    expect(await restarted.pendingCount('owner'), 2);

    await restarted.syncWithCloud(
      'owner', apiA, ownerStillActive: () => true,
    );
    expect(await restarted.pendingCount('owner'), 0);
    await phoneB.syncWithCloud(
      'owner', apiB, ownerStillActive: () => true,
    );
    expect((await phoneB.load('owner')).first.artistKey, 'apple:12');
    expect((await phoneB.find('owner', 'apple:12'))?.isPinned, isTrue);

    await phoneB.setPinned('owner', 'apple:12', false);
    await phoneB.syncWithCloud(
      'owner', apiB, ownerStillActive: () => true,
    );
    await restarted.syncWithCloud(
      'owner', apiA, ownerStillActive: () => true,
    );
    expect((await restarted.find('owner', 'apple:12'))?.isPinned, isFalse);
  });

  test('metadata refresh preserves remote pin unless explicitly changed',
      () async {
    final cloud = _Cloud();
    final store = FollowedArtistStore(keyValueStore: _MemoryStore());
    final api = _FakeArtistApi(cloud, 'owner');
    await store.follow('owner', 'apple:12', 'Old');
    await store.setPinned('owner', 'apple:12', true);
    await store.syncWithCloud('owner', api, ownerStillActive: () => true);
    await store.follow('owner', 'apple:12', 'New');
    await store.syncWithCloud('owner', api, ownerStillActive: () => true);
    expect((await store.find('owner', 'apple:12'))?.isPinned, isTrue);
    expect((await store.find('owner', 'apple:12'))?.displayName, 'New');
    expect((await api.getFollowedArtists())['items'], hasLength(1));
  });

  test('owner separation prevents reading or pinning other libraries',
      () async {
    final store = FollowedArtistStore(keyValueStore: _MemoryStore());
    await store.follow('owner-a', 'apple:88', 'Only A');
    await store.follow('owner-b', 'apple:99', 'Only B');
    expect(await store.setPinned('owner-b', 'apple:88', true), isFalse);
    expect((await store.load('owner-a')).single.artistKey, 'apple:88');
    expect((await store.load('owner-b')).single.artistKey, 'apple:99');
    expect(await store.find('owner-b', 'apple:88'), isNull);
  });

  test('sync refuses account or token changes and keeps pending edits',
      () async {
    final store = FollowedArtistStore(keyValueStore: _MemoryStore());
    final api = _FakeArtistApi(_Cloud(), 'owner-a');
    await store.follow('owner-a', 'apple:88', 'Only A');
    await expectLater(
      store.syncWithCloud('owner-a', api, ownerStillActive: () => false),
      throwsStateError,
    );
    expect(await store.pendingCount('owner-a'), 1);
    await store.syncWithCloud(
      'owner-a', api, ownerStillActive: () => true,
    );
    expect(await store.pendingCount('owner-a'), 0);
    await store.unfollow('owner-a', 'apple:88');
    await store.syncWithCloud(
      'owner-a', api, ownerStillActive: () => true,
    );
    expect(await store.load('owner-a'), isEmpty);
  });
}
