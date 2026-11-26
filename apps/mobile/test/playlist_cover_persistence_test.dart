import 'dart:convert';
import 'dart:io';

import 'package:breezze/app/playlist_store.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('custom cover persists across reload, rename and pin without cloud mutation', () async {
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
    expect(await store.pendingCount('listener-a', playlistId: id), pendingBefore);
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
      store.setLocalCover('listener-a', id, '*' * 100),
      throwsArgumentError,
    );
    await expectLater(
      store.setLocalCover('listener-a', id, 'A' * 750001),
      throwsArgumentError,
    );
    expect((await store.load('listener-a')).single.coverPngBase64, isNull);
  });
}
