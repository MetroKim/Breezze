import 'dart:io';

import 'package:breezze/app/bootstrap.dart' show FavoriteTrack;
import 'package:breezze/app/playlist_store.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';

const aId = '11111111-1111-4111-8111-111111111111';
const bId = '22222222-2222-4222-8222-222222222222';
const a = FavoriteTrack(id: aId, title: 'Song A', artist: 'Artist A');
const b = FavoriteTrack(id: bId, title: 'Song B', artist: 'Artist B');

class FakePlaylistApi extends BreezzeApi {
  FakePlaylistApi() : super(baseUrl: 'https://api.breezze.test') {
    accessToken = 'owner-token';
  }
  final calls = <String>[];
  bool failCreate = false;
  bool changeToken = false;
  bool rejectNextReorder = false;
  bool switchTokenDuringConflictRead = false;
  List<String> currentServerTrackIds = const [];

  @override
  Future<Map<String, dynamic>> createPlaylist(String name, {String? id}) async {
    calls.add('create:$id:$name');
    if (failCreate) {
      failCreate = false;
      throw const BreezzeApiException(code: 'OFFLINE', message: 'Offline');
    }
    if (changeToken) accessToken = 'different-user-token';
    return {'id': id, 'name': name};
  }
  @override
  Future<Map<String, dynamic>> addPlaylistTrack(String playlistId, String trackId) async {
    calls.add('add:$playlistId:$trackId');
    return {'trackId': trackId};
  }
  @override
  Future<Map<String, dynamic>> pinPlaylist(String playlistId, bool pinned) async {
    calls.add('pin:$playlistId:$pinned');
    return {'id': playlistId, 'isPinned': pinned};
  }
  @override
  Future<Map<String, dynamic>> renamePlaylist(String playlistId, String name) async {
    calls.add('rename:$playlistId:$name');
    return {'name': name};
  }
  @override
  Future<Map<String, dynamic>> reorderPlaylistTracks(String playlistId, List<String> trackIds) async {
    calls.add('reorder:$playlistId:${trackIds.join(",")}');
    if (rejectNextReorder) {
      rejectNextReorder = false;
      throw const BreezzeApiException(
        code: 'PLAYLIST_ORDER_MISMATCH', message: 'Changed on another device',
      );
    }
    return {'reordered': true};
  }

  @override
  Future<Map<String, dynamic>> getPlaylist(String playlistId) async {
    calls.add('get:$playlistId');
    if (switchTokenDuringConflictRead) {
      accessToken = 'different-user-token';
    }
    return {
      'id': playlistId,
      'items': [
        for (final id in currentServerTrackIds) {'trackId': id},
      ],
    };
  }
  @override
  Future<void> removePlaylistTrack(String playlistId, String trackId) async {
    calls.add('remove:$playlistId:$trackId');
  }
  @override
  Future<void> deletePlaylist(String playlistId) async {
    calls.add('delete:$playlistId');
  }
}

void main() {
  late Directory root;
  late PlaylistStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('breezze-playlist-test-');
    store = PlaylistStore(documentsDirectory: () async => root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('offline edit journal replays add, rename, reorder, remove in order', () async {
    const owner = 'user-a';
    final id = await store.create(owner, 'Road trip');
    await store.addTrack(owner, id, a);
    await store.addTrack(owner, id, b);
    await store.rename(owner, id, 'Road trip 2');
    await store.reorderTracks(owner, id, 0, 1);
    await store.removeTrack(owner, id, aId);
    expect(await store.pendingCount(owner), 6);
    final api = FakePlaylistApi();
    expect(await store.syncOwner(owner, api, ownerStillActive: () => true), isTrue);
    expect(api.calls, [
      'create:$id:Road trip',
      'add:$id:$aId',
      'add:$id:$bId',
      'rename:$id:Road trip 2',
      'reorder:$id:$bId,$aId',
      'remove:$id:$aId',
    ]);
    expect(await store.pendingCount(owner), 0);
    expect((await store.load(owner)).single.tracks.single.id, bId);
  });

  test('pinned playlists survive restart, retry and remote refresh',
      () async {
    const owner = 'user-a';
    final regular = await store.create(owner, 'Regular');
    final other = await store.create(owner, 'Other');
    expect(await store.setPinned(owner, regular, true), isTrue);
    expect(await store.setPinned(owner, regular, true), isFalse);
    expect((await store.load(owner)).first.id, regular);
    final restored = PlaylistStore(documentsDirectory: () async => root);
    expect((await restored.load(owner)).first.isPinned, isTrue);
    final api = FakePlaylistApi()..failCreate = true;
    expect(await restored.syncOwner(owner, api, ownerStillActive: () => true),
      isFalse);
    expect((await restored.load(owner)).first.isPinned, isTrue);
    expect(await restored.syncOwner(owner, api, ownerStillActive: () => true),
      isTrue);
    expect(api.calls, contains('pin:$regular:true'));
    expect(await restored.pendingCount(owner), 0);
    await restored.mergeRemote(owner, [
      {'id': other, 'name': 'Other', 'isPinned': false, 'items': []},
      {'id': regular, 'name': 'Regular', 'isPinned': true, 'items': []},
    ]);
    expect((await restored.load(owner)).first.id, regular);
    expect(await restored.setPinned(owner, regular, false), isTrue);
    expect((await restored.load(owner)).every((p) => !p.isPinned), isTrue);
  });

  test('pending offline pin wins over stale remote snapshot', () async {
    const owner = 'user-a';
    final id = await store.create(owner, 'Local');
    await store.setPinned(owner, id, true);
    await store.mergeRemote(owner, [
      {'id': id, 'name': 'Stale', 'isPinned': false, 'items': []},
    ]);
    expect((await store.load(owner)).single.isPinned, isTrue);
    expect(await store.pendingCount(owner), 2);
    expect(await store.setPinned('user-b', id, false), isFalse);
  });

  test('pin persists through edits, rename and other-account isolation',
      () async {
    final id = await store.create('user-a', 'Mix');
    await store.setPinned('user-a', id, true);
    await store.addTrack('user-a', id, a);
    await store.rename('user-a', id, 'Renamed');
    await store.addTrack('user-a', id, b);
    await store.reorderTracks('user-a', id, 0, 1);
    await store.removeTrack('user-a', id, aId);
    expect((await store.load('user-a')).single.isPinned, isTrue);
    expect(await store.setPinned('user-b', id, false), isFalse);
    expect((await store.load('user-a')).single.isPinned, isTrue);
  });

  test('unavailable cloud keeps pending operations through restart', () async {
    final id = await store.create('user-a', 'Offline mix');
    await store.addTrack('user-a', id, a);
    final api = FakePlaylistApi()..failCreate = true;
    expect(await store.syncOwner('user-a', api, ownerStillActive: () => true), isFalse);
    expect(await store.pendingCount('user-a'), 2);
    final reloaded = PlaylistStore(documentsDirectory: () async => root);
    expect((await reloaded.load('user-a')).single.name, 'Offline mix');
    expect(await reloaded.syncOwner('user-a', api, ownerStillActive: () => true), isTrue);
    expect(await reloaded.pendingCount('user-a'), 0);
    expect(api.calls.length, 3); // failed create, safe retry, add
  });

  test('cross-device cloud snapshot restores tracks without crossing accounts', () async {
    final otherRoot = await Directory.systemTemp.createTemp('breezze-device-b-');
    try {
      final remoteDevice = PlaylistStore(documentsDirectory: () async => otherRoot);
      final unrelated = await remoteDevice.create('user-b', 'Private B');
      final id = await store.create('user-a', 'Home mix');
      await store.addTrack('user-a', id, a);
      await store.syncOwner('user-a', FakePlaylistApi(), ownerStillActive: () => true);
      await remoteDevice.mergeRemote('user-a', [{
        'id': id, 'name': 'Home mix',
        'items': [{'track': {'id': aId, 'title': 'Song A',
          'artist': {'name': 'Artist A'}, 'duration': 180}}],
      }]);
      expect((await remoteDevice.load('user-a')).single.tracks.single.id, aId);
      expect((await remoteDevice.load('user-b')).single.id, unrelated);
    } finally {
      await otherRoot.delete(recursive: true);
    }
  });

  test('unsynced edits survive stale cloud hydration', () async {
    final id = await store.create('user-a', 'Local');
    await store.addTrack('user-a', id, a);
    await store.mergeRemote('user-a', [{'id': id, 'name': 'Stale', 'items': []}]);
    expect((await store.load('user-a')).single.tracks.single.id, aId);
    expect((await store.load('user-a')).single.name, 'Local');
    expect(await store.replaceTracks('user-a', id, []), isFalse);
    expect(await store.pendingCount('user-a'), 2);
  });

  test('token changes cannot acknowledge an operation under another account', () async {
    final id = await store.create('user-a', 'Private A');
    await store.addTrack('user-a', id, a);
    final api = FakePlaylistApi()..changeToken = true;
    expect(await store.syncOwner('user-a', api, ownerStillActive: () => true), isFalse);
    expect(api.calls.length, 1);
    expect(await store.pendingCount('user-a'), 2);
  });

  test('legacy numeric offline ID is upgraded without losing edits', () async {
    await store.create('user-a', 'Old', id: '1234567890');
    await store.addTrack('user-a', '1234567890', a);
    final api = FakePlaylistApi();
    expect(await store.syncOwner('user-a', api, ownerStillActive: () => true), isTrue);
    expect((await store.load('user-a')).single.id, isNot('1234567890'));
    expect((await store.load('user-a')).single.tracks.single.id, aId);
    expect(await store.pendingCount('user-a'), 0);
    expect(api.calls.length, 2);
  });

  test('offline reorder preserves a song added by another device', () async {
    final id = await store.create('user-a', 'Friends');
    await store.addTrack('user-a', id, a);
    await store.addTrack('user-a', id, b);
    final api = FakePlaylistApi();
    expect(await store.syncOwner('user-a', api,
      ownerStillActive: () => true), isTrue);
    api.calls.clear();
    await store.reorderTracks('user-a', id, 0, 1);
    const cId = '33333333-3333-4333-8333-333333333333';
    api.currentServerTrackIds = [aId, bId, cId];
    api.rejectNextReorder = true;

    expect(await store.syncOwner('user-a', api,
      ownerStillActive: () => true), isTrue);
    expect(api.calls, [
      'reorder:$id:$bId,$aId',
      'get:$id',
      'reorder:$id:$bId,$aId,$cId',
    ]);
    expect(await store.pendingCount('user-a'), 0);
  });

  test('offline reorder rebases when another device removed a song', () async {
    final id = await store.create('user-a', 'Friends');
    await store.addTrack('user-a', id, a);
    await store.addTrack('user-a', id, b);
    final api = FakePlaylistApi();
    await store.syncOwner('user-a', api, ownerStillActive: () => true);
    api.calls.clear();
    await store.reorderTracks('user-a', id, 0, 1);
    api.currentServerTrackIds = [bId];
    api.rejectNextReorder = true;
    expect(await store.syncOwner('user-a', api,
      ownerStillActive: () => true), isTrue);
    expect(api.calls.last, 'reorder:$id:$bId');
    expect(await store.pendingCount('user-a'), 0);
  });

  test('token switch during reorder rebase never retries as another user',
      () async {
    final id = await store.create('user-a', 'Private');
    await store.addTrack('user-a', id, a);
    await store.addTrack('user-a', id, b);
    final api = FakePlaylistApi();
    await store.syncOwner('user-a', api, ownerStillActive: () => true);
    api.calls.clear();
    await store.reorderTracks('user-a', id, 0, 1);
    api.currentServerTrackIds = [aId, bId];
    api.rejectNextReorder = true;
    api.switchTokenDuringConflictRead = true;
    expect(await store.syncOwner('user-a', api,
      ownerStillActive: () => true), isFalse);
    expect(api.calls, ['reorder:$id:$bId,$aId', 'get:$id']);
    expect(await store.pendingCount('user-a'), 1);
  });

  test('one multi-select commits only chosen memberships and journals edits',
      () async {
    final first = await store.create('user-a', 'Daily mix');
    final second = await store.create('user-a', 'Road trip');
    final third = await store.create('user-a', 'Workout');
    final other = await store.create('user-b', 'Private playlist');

    expect(await store.addTrackToMany(
      'user-a', [first, second, first, 'unknown-playlist'], a,
    ), 2);
    expect(await store.addTrackToMany('user-a', [first, second], a), 0);
    expect(await store.addTrackToMany('user-a', [second, third], b), 2);
    expect(await store.addTrackToMany('user-a', [], a), 0);

    final own = {for (final p in await store.load('user-a')) p.id: p};
    expect(own[first]!.tracks.map((t) => t.id), [aId]);
    expect(own[second]!.tracks.map((t) => t.id), [aId, bId]);
    expect(own[third]!.tracks.map((t) => t.id), [bId]);
    expect((await store.load('user-b')).single.id, other);
    expect((await store.load('user-b')).single.tracks, isEmpty);
    expect(await store.pendingCount('user-a'), 7); // 3 creates, 4 adds

    final restarted = PlaylistStore(documentsDirectory: () async => root);
    final restored = {for (final p in await restarted.load('user-a')) p.id: p};
    expect(restored[second]!.tracks.map((t) => t.id), [aId, bId]);
    expect(await restarted.pendingCount('user-a'), 7);

    final api = FakePlaylistApi();
    expect(await restarted.syncOwner('user-a', api,
      ownerStillActive: () => true), isTrue);
    expect(api.calls.take(3), [
      'create:$first:Daily mix',
      'create:$second:Road trip',
      'create:$third:Workout',
    ]);
    // Each membership is delivered exactly once. Different playlists may be
    // iterated in persistent display order instead of the selection order.
    expect(api.calls.skip(3).toSet(), {
      'add:$first:$aId',
      'add:$second:$aId',
      'add:$second:$bId',
      'add:$third:$bId',
    });
    expect(api.calls, hasLength(7));
    expect(await restarted.pendingCount('user-a'), 0);
    expect(await restarted.pendingCount('user-b'), 1);
  });

  test('multi-add recognizes canonical IDs of previously resolved songs',
      () async {
    const providerId = 'bz:youtube_music:original';
    final mapped = PlaylistStore(
      documentsDirectory: () async => root,
      cachedCanonicalId: (external) async =>
          external == providerId ? aId : null,
    );
    final list = await mapped.create('user-a', 'Mapped songs');
    await mapped.addTrack('user-a', list, a);
    expect(await mapped.addTrackToMany('user-a', [list],
      const FavoriteTrack(id: providerId, title: 'Song A',
        artist: 'Artist A')), 0);
    expect((await mapped.load('user-a')).single.tracks, hasLength(1));
    expect(await mapped.pendingCount('user-a'), 2);
  });

  test('multi-select offline journals survive stale remote hydration', () async {
    final first = await store.create('user-a', 'First');
    final second = await store.create('user-a', 'Second');
    expect(await store.addTrackToMany('user-a', [first, second], a), 2);
    await store.mergeRemote('user-a', [
      {'id': first, 'name': 'Stale first', 'items': []},
      {'id': second, 'name': 'Stale second', 'items': []},
    ]);
    final local = await store.load('user-a');
    expect(local.every((playlist) => playlist.tracks.single.id == aId), isTrue);
    expect(await store.pendingCount('user-a'), 4);
  });

  test('guest multi-select remains private without upload work', () async {
    final first = await store.create('guest', 'Local one');
    final second = await store.create('guest', 'Local two');
    expect(await store.addTrackToMany('guest', [first, second], a), 2);
    expect(await store.pendingCount('guest'), 0);
    expect((await store.load('guest')).every((p) => p.tracks.length == 1),
      isTrue);
  });

  test('guest playlists remain device-only', () async {
    await store.create('guest', 'Local');
    expect(await store.pendingCount('guest'), 0);
    final api = FakePlaylistApi();
    expect(await store.syncOwner('guest', api, ownerStillActive: () => true), isFalse);
    expect(api.calls, isEmpty);
  });
}
