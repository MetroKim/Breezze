import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedLyricsHttp implements LyricsHttp {
  @override
  Future<String> getText(String url) async => throw StateError('not used');
}

void main() {
  late Directory root;
  late DownloadsLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('breezze-downloads-');
    library = DownloadsLibrary(
      root: root,
      lyrics: LyricsProvider(_UnusedLyricsHttp()),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('lists only assets owned by the requested account', () async {
    final alice = Directory('${root.path}/bz:alice-track');
    final bob = Directory('${root.path}/bz:bob-track');
    await alice.create();
    await bob.create();

    await File('${alice.path}/audio.m4a').writeAsBytes([1, 2, 3]);
    await File('${bob.path}/audio.m4a').writeAsBytes([4, 5, 6]);
    await File('${alice.path}/meta.json').writeAsString(jsonEncode({
      'title': 'Alice track',
      'artist': 'Artist A',
      'ownerId': 'alice',
      'catalogTrackId': 'catalog-a',
      'rightsExpiresAtUtc': null,
    }));
    await File('${bob.path}/meta.json').writeAsString(jsonEncode({
      'title': 'Bob track',
      'artist': 'Artist B',
      'ownerId': 'bob',
      'catalogTrackId': 'catalog-b',
      'rightsExpiresAtUtc': null,
    }));

    final tracks = await library.list(ownerId: 'alice');

    expect(tracks, hasLength(1));
    expect(tracks.single.title, 'Alice track');
    expect(tracks.single.ownerId, 'alice');
    expect(tracks.single.catalogTrackId, 'catalog-a');
    expect(tracks.single.audioPath, '${alice.path}/audio.m4a');
  });

  test('preserves rights expiry metadata for offline enforcement', () async {
    final trackDir = Directory('${root.path}/bz:expiring-track');
    await trackDir.create();
    final expiry = DateTime.utc(2027, 1, 1);
    await File('${trackDir.path}/audio.m4a').writeAsBytes([1]);
    await File('${trackDir.path}/meta.json').writeAsString(jsonEncode({
      'title': 'Expiring track',
      'artist': 'Artist',
      'ownerId': 'user-1',
      'catalogTrackId': 'catalog-track-1',
      'rightsExpiresAtUtc': expiry.toIso8601String(),
    }));

    final tracks = await library.list(ownerId: 'user-1');

    expect(tracks.single.rightsExpiresAtUtc, expiry);
  });

  test('does not expose legacy metadata without an owner', () async {
    final legacy = Directory('${root.path}/legacy-track');
    await legacy.create();
    await File('${legacy.path}/meta.json').writeAsString(
      jsonEncode({'title': 'Legacy', 'artist': 'Unknown'}),
    );

    expect(await library.list(ownerId: 'user-1'), isEmpty);
  });
}
