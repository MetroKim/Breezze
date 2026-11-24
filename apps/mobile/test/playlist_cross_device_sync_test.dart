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
  Future<Map<String, dynamic>> renamePlaylist(String playlistId, String name) async {
    calls.add('rename:$playlistId:$name');
    return {'name': name};
  }
  @override
  Future<Map<String, dynamic>> reorderPlaylistTracks(String playlistId, List<String> trackIds) async {
    calls.add('reorder:$playlistId:${trackIds.join(",")}');
    return {'reordered': true};
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

  test('guest playlists remain device-only', () async {
    await store.create('guest', 'Local');
    expect(await store.pendingCount('guest'), 0);
    final api = FakePlaylistApi();
    expect(await store.syncOwner('guest', api, ownerStillActive: () => true), isFalse);
    expect(api.calls, isEmpty);
  });
}
