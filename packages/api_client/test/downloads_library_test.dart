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

    var receivedRange = '';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      receivedRange = request.headers.value('range') ?? '';
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
        ..set('content-type', 'audio/mp4')
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
      rightsExpiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    expect(ok, isTrue);
    expect(receivedRange, 'bytes=3-');
    expect(await File('${trackDir.path}/audio.m4a').readAsString(), 'abcdef');
    expect(await partial.exists(), isFalse);
  });


  test('expired grant or non-audio HTTP response cannot create offline music', () async {
    final track = BzTrack(
      id: 'licensed-aac',
      title: 'Licensed track',
      artist: 'Breezze Artist',
      duration: const Duration(minutes: 3),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<h1>not licensed audio</h1>');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final url = 'http://${server.address.address}:${server.port}/audio';

    expect(await library.download(
      track, downloadUrl: url, ownerId: 'owner-1',
      catalogTrackId: track.id,
      rightsExpiresAtUtc: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    ), isFalse);
    expect(await library.download(
      track, downloadUrl: url, ownerId: 'owner-1',
      catalogTrackId: track.id,
      rightsExpiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ), isFalse);
    expect(await library.list(ownerId: 'owner-1'), isEmpty);
    expect(await File('${root.path}/licensed-aac/audio.m4a').exists(), isFalse);
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
