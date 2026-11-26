import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

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


  test('resumes a partial authorized download using HTTP byte ranges', () async {
    final track = BzTrack(
      id: 'catalog-resume',
      title: 'Resume track',
      artist: 'Artist',
      duration: const Duration(minutes: 3),
    );
    final trackDir = Directory('${root.path}/catalog-resume');
    await trackDir.create();
    final partial = File('${trackDir.path}/audio.part');
    await partial.writeAsBytes(utf8.encode('abc'));
    await File('${trackDir.path}/audio.part.identity.json').writeAsString(jsonEncode({
      'ownerId': 'user-1',
      'catalogTrackId': 'catalog-resume',
      'assetVersion': 'encoded-v1',
    }));

    var receivedRange = '';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      receivedRange = request.headers.value('range') ?? '';
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
        ..set('content-range', 'bytes 3-5/6')
        ..contentLength = 3;
      request.response.add(utf8.encode('def'));
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
    });

    final ok = await library.download(
      track,
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'user-1',
      catalogTrackId: 'catalog-resume',
      assetVersion: 'encoded-v1',
    );

    expect(ok, isTrue);
    expect(receivedRange, 'bytes=3-');
    expect(await File('${trackDir.path}/audio.m4a').readAsString(), 'abcdef');
    expect(await partial.exists(), isFalse);
  });

  test('stale fragment cannot resume when the authorized asset version changes', () async {
    const id = 'catalog-versioned';
    final track = BzTrack(id: id, title: 'Fresh version', artist: 'A');
    final folder = Directory('${root.path}/$id');
    await folder.create();
    await File('${folder.path}/audio.part').writeAsString('oldbytes');
    await File('${folder.path}/audio.part.identity.json').writeAsString(jsonEncode({
      'ownerId': 'user-1',
      'catalogTrackId': id,
      'assetVersion': 'previous-version',
    }));
    String? range;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      range = request.headers.value('range');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 5
        ..add(utf8.encode('fresh'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    expect(await library.download(
      track,
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'user-1',
      catalogTrackId: id,
      assetVersion: 'new-version',
    ), isTrue);
    expect(range, isNull);
    expect(await File('${folder.path}/audio.m4a').readAsString(), 'fresh');
    final meta = jsonDecode(await File('${folder.path}/meta.json').readAsString());
    expect(meta['assetVersion'], 'new-version');
  });

  test('an unversioned partial cannot silently join a different recording', () async {
    const id = 'catalog-unversioned';
    final track = BzTrack(id: id, title: 'Replaced', artist: 'A');
    final folder = Directory('${root.path}/$id');
    await folder.create();
    await File('${folder.path}/audio.part').writeAsString('stale');
    String? range;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      range = request.headers.value('range');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 3
        ..add(utf8.encode('new'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    expect(await library.download(
      track,
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'user-1',
      catalogTrackId: id,
    ), isTrue);
    expect(range, isNull);
    expect(await File('${folder.path}/audio.m4a').readAsString(), 'new');
  });

  test('resume rejects a malformed HTTP Content-Range rather than saving corrupt audio', () async {
    const id = 'catalog-bad-range';
    final track = BzTrack(id: id, title: 'Bad range', artist: 'A');
    final folder = Directory('${root.path}/$id');
    await folder.create();
    await File('${folder.path}/audio.part').writeAsString('abc');
    await File('${folder.path}/audio.part.identity.json').writeAsString(jsonEncode({
      'ownerId': 'user-1',
      'catalogTrackId': id,
      'assetVersion': 'v1',
    }));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('content-range', 'bytes 4-6/7')
        ..headers.contentLength = 3
        ..add(utf8.encode('def'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    expect(await library.download(
      track,
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'user-1',
      catalogTrackId: id,
      assetVersion: 'v1',
    ), isFalse);
    expect(await File('${folder.path}/audio.m4a').exists(), isFalse);
    expect(await File('${folder.path}/audio.part').readAsString(), 'abc');
  });

  test('valid signed asset SHA256 permits a complete authorized offline file', () async {
    const id = 'catalog-hash-ok';
    const actualDigest = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 3
        ..add(utf8.encode('abc'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    expect(await library.download(
      BzTrack(id: id, title: 'Verified audio', artist: 'A'),
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'user-1',
      catalogTrackId: id,
      assetVersion: actualDigest,
    ), isTrue);
    final folder = Directory('${root.path}/$id');
    expect(await File('${folder.path}/audio.m4a').readAsString(), 'abc');
  });

  test('wrong signed SHA256 deletes audio and refuses to mark it downloaded', () async {
    const id = 'catalog-hash-bad';
    const incorrectDigest = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 3
        ..add(utf8.encode('abc'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    expect(await library.download(
      BzTrack(id: id, title: 'Invalid audio', artist: 'A'),
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'user-1',
      catalogTrackId: id,
      assetVersion: incorrectDigest,
    ), isFalse);
    expect(await File('${root.path}/$id/audio.m4a').exists(), isFalse);
    expect(await library.list(ownerId: 'user-1'), isEmpty);
  });

  test('protected download commits only AES-GCM ciphertext and owner metadata', () async {
    const id = 'protected-audio';
    final track = BzTrack(id: id, title: 'Original song', artist: 'Breezze QA');
    final cipher = BreezzeOfflineAudioCipher(
      SecretKey(List<int>.filled(32, 0x23)),
    );
    final protectedLibrary = DownloadsLibrary(
      root: root,
      lyrics: LyricsProvider(_UnusedLyricsHttp()),
      protectAudio: ({
        required File plaintextFile,
        required File encryptedFile,
        required String ownerId,
        required String catalogTrackId,
        String? assetVersion,
      }) async {
        await cipher.encryptFile(
          input: plaintextFile,
          output: encryptedFile,
          ownerId: ownerId,
          catalogTrackId: catalogTrackId,
          assetVersion: assetVersion,
        );
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 3
        ..add(utf8.encode('abc'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final lease = DateTime.now().toUtc().add(const Duration(hours: 1));
    expect(await protectedLibrary.download(
      track,
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'listener-a',
      catalogTrackId: id,
      rightsExpiresAtUtc: lease,
    ), isTrue);

    final folder = Directory('${root.path}/$id');
    expect(await File('${folder.path}/audio.m4a').exists(), isFalse);
    expect(await File('${folder.path}/audio.part').exists(), isFalse);
    final list = await protectedLibrary.list(ownerId: 'listener-a');
    expect(list, hasLength(1));
    expect(list.single.audioPath, '${folder.path}/audio.bza');
    expect(await protectedLibrary.list(ownerId: 'listener-b'), isEmpty);
    final decrypted = await cipher.decryptRange(
      encrypted: File(list.single.audioPath),
      ownerId: 'listener-a',
      catalogTrackId: id,
    ).toList();
    expect(decrypted.expand((e) => e).toList(), utf8.encode('abc'));
  });

  test('encryption failure does not silently save plaintext audio', () async {
    const id = 'protected-fail';
    final protectedLibrary = DownloadsLibrary(
      root: root,
      lyrics: LyricsProvider(_UnusedLyricsHttp()),
      protectAudio: ({
        required File plaintextFile,
        required File encryptedFile,
        required String ownerId,
        required String catalogTrackId,
        String? assetVersion,
      }) async {
        throw StateError('Simulated unavailable platform keystore');
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 3
        ..add(utf8.encode('abc'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    expect(await protectedLibrary.download(
      BzTrack(id: id, title: 'Fail secure', artist: 'Breezze'),
      downloadUrl: 'http://${server.address.address}:${server.port}/audio',
      ownerId: 'listener-a',
      catalogTrackId: id,
    ), isFalse);
    final folder = Directory('${root.path}/$id');
    expect(await File('${folder.path}/audio.m4a').exists(), isFalse);
    expect(await File('${folder.path}/audio.part').exists(), isFalse);
    expect(await protectedLibrary.list(ownerId: 'listener-a'), isEmpty);
  });

  test('legacy authorized plaintext is migrated to BZA8 before encrypted-only listing', () async {
    const id = 'catalog-legacy-audio';
    final dir = Directory('${root.path}/$id');
    await dir.create();
    await File('${dir.path}/audio.m4a').writeAsString('legacy audio');
    await File('${dir.path}/meta.json').writeAsString(jsonEncode({
      'ownerId': 'user-a',
      'catalogTrackId': id,
      'title': 'Legacy audio',
      'artist': 'Breezze',
      'rightsExpiresAtUtc':
          DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
    }));
    final cipher = BreezzeOfflineAudioCipher(
      SecretKey(List<int>.filled(32, 0x34)),
    );
    final protectedLibrary = DownloadsLibrary(
      root: root,
      lyrics: LyricsProvider(_UnusedLyricsHttp()),
      protectAudio: ({
        required File plaintextFile,
        required File encryptedFile,
        required String ownerId,
        required String catalogTrackId,
        String? assetVersion,
      }) async {
        await cipher.encryptFile(
          input: plaintextFile, output: encryptedFile,
          ownerId: ownerId, catalogTrackId: catalogTrackId,
          assetVersion: assetVersion,
        );
      },
    );
    expect(await protectedLibrary.protectLegacy(ownerId: 'user-b'), 0);
    expect(await File('${dir.path}/audio.m4a').exists(), isTrue);
    expect(await protectedLibrary.protectLegacy(ownerId: 'user-a'), 1);
    expect(await File('${dir.path}/audio.m4a').exists(), isFalse);
    expect((await protectedLibrary.list(
      ownerId: 'user-a', encryptedOnly: true,
    )).single.audioPath, '${dir.path}/audio.bza');
    final source = await cipher.decryptRange(
      encrypted: File('${dir.path}/audio.bza'),
      ownerId: 'user-a',
      catalogTrackId: id,
    ).toList();
    expect(utf8.decode(source.expand((e) => e).toList()), 'legacy audio');
  });

  test('legacy migration does not expose plaintext if secure key store fails', () async {
    const id = 'legacy-keystore-fail';
    final dir = Directory('${root.path}/$id');
    await dir.create();
    await File('${dir.path}/audio.m4a').writeAsString('legacy');
    await File('${dir.path}/meta.json').writeAsString(jsonEncode({
      'ownerId': 'user-a',
      'catalogTrackId': id,
    }));
    final protectedLibrary = DownloadsLibrary(
      root: root,
      lyrics: LyricsProvider(_UnusedLyricsHttp()),
      protectAudio: ({
        required File plaintextFile,
        required File encryptedFile,
        required String ownerId,
        required String catalogTrackId,
        String? assetVersion,
      }) async {
        throw StateError('No secure key storage');
      },
    );
    expect(await protectedLibrary.protectLegacy(ownerId: 'user-a'), 0);
    expect(await File('${dir.path}/audio.m4a').exists(), isTrue);
    expect(await protectedLibrary.list(
      ownerId: 'user-a', encryptedOnly: true,
    ), isEmpty);
  });

  test('lists only assets owned by the requested account', () async {
    final alice = Directory('${root.path}/bz_alice-track');
    final bob = Directory('${root.path}/bz_bob-track');
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
    final trackDir = Directory('${root.path}/bz_expiring-track');
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

  test('licensed video transfer uses the existing byte-range downloader', () async {
    const assetId = '123e4567-e89b-42d3-a456-426614174000';
    final folder = Directory('${root.path}/videos/$assetId');
    await folder.create(recursive: true);
    await File('${folder.path}/video.part').writeAsBytes(utf8.encode('abc'));
    var range = '';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      range = request.headers.value('range') ?? '';
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
        ..set('content-type', 'video/mp4')
        ..set('content-range', 'bytes 3-5/6')
        ..contentLength = 3;
      request.response.add(utf8.encode('def'));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final expiry = DateTime.now().toUtc().add(const Duration(days: 1));
    final ok = await library.downloadVideo(
      videoAssetId: assetId,
      title: 'Licensed music video',
      ownerId: 'owner-a',
      downloadUrl: 'http://${server.address.address}:${server.port}/video',
      rightsExpiresAtUtc: expiry,
    );
    expect(ok, isTrue);
    expect(range, 'bytes=3-');
    expect(await File('${folder.path}/video.mp4').readAsString(), 'abcdef');
    expect(await library.list(ownerId: 'owner-a'), isEmpty);
    expect(await library.listVideos(ownerId: 'owner-b'), isEmpty);
    final videos = await library.listVideos(ownerId: 'owner-a');
    expect(videos, hasLength(1));
    expect(videos.single.videoAssetId, assetId);
    expect(videos.single.title, 'Licensed music video');
    expect(videos.single.rightsExpiresAtUtc, expiry);
    final renewed = expiry.add(const Duration(hours: 6));
    await library.updateVideoOfflineLease(assetId, renewed);
    expect((await library.listVideos(ownerId: 'owner-a')).single.rightsExpiresAtUtc, renewed);
    await library.removeVideo(assetId);
    expect(await library.listVideos(ownerId: 'owner-a'), isEmpty);
  });

  test('video download rejects unexpected media type and expired lease', () async {
    const assetId = '123e4567-e89b-42d3-a456-426614174000';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write('not a video');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final url = 'http://${server.address.address}:${server.port}/video';
    expect(await library.downloadVideo(
      videoAssetId: assetId, title: 'Reject',
      ownerId: 'owner-a', downloadUrl: url,
      rightsExpiresAtUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    ), isFalse);
    expect(await library.downloadVideo(
      videoAssetId: assetId, title: 'Reject',
      ownerId: 'owner-a', downloadUrl: url,
      rightsExpiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ), isFalse);
    expect(await library.listVideos(ownerId: 'owner-a'), isEmpty);
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
