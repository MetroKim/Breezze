import 'dart:convert';
import 'dart:io';

import 'package:breezze/app/playlist_store.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoverSyncApi extends BreezzeApi {
  _CoverSyncApi() : super(baseUrl: 'https://api.breezze.test') {
    accessToken = 'test-owner-session';
  }

  final Map<String, String?> remoteCovers = {};

  @override
  Future<Map<String, dynamic>> createPlaylist(String name, {String? id}) async =>
      {'id': id, 'name': name};

  @override
  Future<Map<String, dynamic>> setPlaylistCover(
    String playlistId, String? coverPngBase64,
  ) async {
    remoteCovers[playlistId] = coverPngBase64;
    return {'id': playlistId, 'coverPngBase64': coverPngBase64};
  }
}

void main() {
  late Directory root;
  late PlaylistStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('breezze-cover-test-');
    store = PlaylistStore(documentsDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('cover remains atomic across reload, rename, pin and clear mutation journal', () async {
    final id = await store.create('listener-a', 'My Mix');
    final cover = base64Encode(List<int>.filled(512, 77));
    expect(await store.setLocalCover('listener-a', id, cover), isTrue);
    expect((await store.load('listener-a')).single.coverPngBase64, cover);

    await store.rename('listener-a', id, 'New name');
    await store.setPinned('listener-a', id, true);
    final renamed = (await store.load('listener-a')).single;
    expect(renamed.name, 'New name');
    expect(renamed.isPinned, isTrue);
    expect(renamed.coverPngBase64, cover);

    final pendingBefore = await store.pendingCount('listener-a', playlistId: id);
    expect(await store.setLocalCover('listener-a', id, null), isTrue);
    expect((await store.load('listener-a')).single.coverPngBase64, isNull);
    expect(await store.pendingCount('listener-a', playlistId: id), pendingBefore + 1);
  });

  test('cover belongs to one listener and another playlist cannot read it', () async {
    const sameId = '11111111-1111-4111-8111-111111111111';
    await store.create('listener-a', 'Shared name', id: sameId);
    await store.create('listener-b', 'Shared name', id: sameId);
    final cover = base64Encode(List<int>.filled(128, 4));
    expect(await store.setLocalCover('listener-a', sameId, cover), isTrue);
    expect((await store.load('listener-a')).single.coverPngBase64, cover);
    expect((await store.load('listener-b')).single.coverPngBase64, isNull);
  });

  test('rejects oversized, invalid and unknown-playlist edits', () async {
    const missing = '22222222-2222-4222-8222-222222222222';
    expect(await store.setLocalCover('listener-a', missing, 'YWJj'), isFalse);
    final id = await store.create('listener-a', 'Original');
    await expectLater(
      store.setLocalCover('listener-a', id, List<String>.filled(100, '*').join()),
      throwsArgumentError,
    );
    await expectLater(
      store.setLocalCover('listener-a', id, List<String>.filled(350001, 'A').join()),
      throwsArgumentError,
    );
    expect((await store.load('listener-a')).single.coverPngBase64, isNull);
  });
  test('offline cover sync replays across devices and respects signed-in owner', () async {
    const owner = 'listener-a';
    final id = await store.create(owner, 'Offline covers');
    const cover = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mP8/x8AAwMCAO+/+5AAAAAASUVORK5CYII=';
    await store.setLocalCover(owner, id, cover);
    final api = _CoverSyncApi();
    expect(await store.pendingCount(owner), 2);
    expect(await store.syncOwner(owner, api, ownerStillActive: () => true), true);
    expect(api.remoteCovers[id], cover);
    expect(await store.pendingCount(owner), 0);

    final deviceBRoot = Directory('${root.path}/device-b');
    final deviceB = PlaylistStore(documentsDirectory: () async => deviceBRoot);
    await deviceB.mergeRemote(owner, [{
      'id': id, 'name': 'Offline covers', 'items': [],
      'coverPngBase64': api.remoteCovers[id],
    }]);
    expect((await deviceB.load(owner)).single.coverPngBase64, cover);
    expect(await deviceB.load('listener-b'), isEmpty);

    await deviceB.setLocalCover(owner, id, null);
    expect(await deviceB.syncOwner(owner, api, ownerStillActive: () => true), true);
    expect(api.remoteCovers[id], isNull);
    await store.mergeRemote(owner, [{
      'id': id, 'name': 'Offline covers', 'items': [],
      'coverPngBase64': api.remoteCovers[id],
    }]);
    expect((await store.load(owner)).single.coverPngBase64, isNull);
  });

}
