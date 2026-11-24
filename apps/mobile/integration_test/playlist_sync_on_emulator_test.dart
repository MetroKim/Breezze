import 'dart:io';
import 'dart:math';

import 'package:breezze/app/bootstrap.dart' show FavoriteTrack;
import 'package:breezze/app/playlist_store.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _edge = String.fromEnvironment(
  'BREEZZE_API_URL',
  defaultValue: 'https://breezze-api-edge.ykw8vmq7ph.workers.dev',
);

class _TemporaryAccount {
  _TemporaryAccount(this.api, this.email, this.password);

  final BreezzeApi api;
  final String email;
  final String password;
  bool creationAttempted = false;
  String? userId;

  Future<AuthResponse> register() async {
    creationAttempted = true;
    final result = await api.register(email, password,
        displayName: 'Breezze Android QA');
    api.accessToken = result.accessToken;
    userId = result.userId;
    return result;
  }

  Future<void> cleanup() async {
    if (!creationAttempted) return;
    if (api.accessToken == null) {
      // Recovery for registration that completed server-side before a
      // device network timeout prevented receiving the token.
      try {
        api.accessToken = (await api.login(email, password)).accessToken;
      } on BreezzeApiException catch (error) {
        if (error.code == 'INVALID_CREDENTIALS' ||
            error.code == 'HTTP_401') {
          return; // No account was created.
        }
        rethrow;
      }
    }
    await api.deleteAccount(password: password);
    await expectLater(api.me(), throwsA(isA<BreezzeApiException>()));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android emulator: offline persistence and two-device live '
      'playlist synchronization', (tester) async {
    final seed = DateTime.now().microsecondsSinceEpoch.toString() +
        Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final root = await Directory(
      (await getApplicationDocumentsDirectory()).path +
          '/breezze-qa-' + seed,
    ).create(recursive: true);

    final apiA = BreezzeApi(baseUrl: _edge);
    final apiOther = BreezzeApi(baseUrl: _edge);
    final apiSecond = BreezzeApi(baseUrl: _edge);
    final accounts = <_TemporaryAccount>[
      _TemporaryAccount(
        apiA,
        'breezze-android-qa-' + seed + '-a@example.com',
        'QA-Android-' + seed + '-A!Strong',
      ),
      _TemporaryAccount(
        apiOther,
        'breezze-android-qa-' + seed + '-b@example.com',
        'QA-Android-' + seed + '-B!Strong',
      ),
    ];
    try {
      final owner = accounts[0];
      final other = accounts[1];
      final ownerAuth = await owner.register();
      await other.register();
      final secondSession = await apiSecond.login(owner.email, owner.password);
      apiSecond.accessToken = secondSession.accessToken;
      expect(ownerAuth.accessToken, isNot(secondSession.accessToken));
      expect(ownerAuth.userId, equals(secondSession.userId));

      final canonicalA = await apiA.resolveCatalogTrack(
        externalId: 'bz:youtube_music:wZaotY2V3gY',
        source: 'youtube_music',
        title: 'Love',
        artistName: 'Keyshia Cole',
        durationSec: 256,
      );
      final canonicalB = await apiA.resolveCatalogTrack(
        externalId: 'bz:youtube_music:qH1wbp-FASo',
        source: 'youtube_music',
        title: 'Love in This Club (feat. Young Jeezy)',
        artistName: 'Usher',
        durationSec: 260,
      );
      final tracks = [
        FavoriteTrack(
          id: canonicalA['id'] as String,
          title: 'Love',
          artist: 'Keyshia Cole',
          durationMs: 256000,
        ),
        FavoriteTrack(
          id: canonicalB['id'] as String,
          title: 'Love in This Club (feat. Young Jeezy)',
          artist: 'Usher',
          durationMs: 260000,
        ),
      ];
      expect(tracks[0].id, isNot(tracks[1].id));

      final dirA = await Directory(root.path + '/phone-a')
          .create(recursive: true);
      final dirB = await Directory(root.path + '/phone-b')
          .create(recursive: true);
      PlaylistStore phoneA = PlaylistStore(
        documentsDirectory: () async => dirA,
      );
      final phoneB = PlaylistStore(
        documentsDirectory: () async => dirB,
      );
      final userId = owner.userId!;
      final playlistId = await phoneA.create(userId, 'Offline on phone A');
      await phoneA.addTrack(userId, playlistId, tracks[0]);
      await phoneA.addTrack(userId, playlistId, tracks[1]);
      await phoneA.rename(userId, playlistId, 'Recovered on phone B');
      expect(await phoneA.pendingCount(userId), 4);

      // Simulate the device losing its network while offline edits remain
      // durable on its real Android filesystem.
      final offlineApi = BreezzeApi(
        baseUrl: _edge,
        client: MockClient((_) async => http.Response(
          '{"error":"OFFLINE"}', 503,
        )),
      )..accessToken = ownerAuth.accessToken;
      expect(await phoneA.syncOwner(
        userId, offlineApi, ownerStillActive: () => true,
      ), isFalse);
      expect(await phoneA.pendingCount(userId), 4);

      // Process restart: build a fresh store over the SAME Android files.
      phoneA = PlaylistStore(documentsDirectory: () async => dirA);
      expect((await phoneA.load(userId)).single.tracks.length, 2);
      expect(await phoneA.syncOwner(
        userId, apiA, ownerStillActive: () => true,
      ), isTrue);
      expect(await phoneA.pendingCount(userId), 0);

      // Device B downloads only this owner's cloud state, including songs.
      await phoneB.mergeRemote(userId, await apiSecond.playlists());
      final restored = (await phoneB.load(userId)).single;
      expect(restored.id, playlistId);
      expect(restored.name, 'Recovered on phone B');
      expect(restored.tracks.map((track) => track.id).toList(), [
        tracks[0].id, tracks[1].id,
      ]);
      expect((await apiOther.playlists())
          .any((playlist) => playlist['id'] == playlistId), isFalse);
      await expectLater(
        apiOther.getPlaylist(playlistId),
        throwsA(isA<BreezzeApiException>()),
      );

      // Reorder on B; A gets B's order after a new cloud reconciliation.
      await phoneB.reorderTracks(userId, playlistId, 0, 1);
      expect(await phoneB.syncOwner(
        userId, apiSecond, ownerStillActive: () => true,
      ), isTrue);
      await phoneA.mergeRemote(userId, await apiA.playlists());
      expect((await phoneA.load(userId)).single.tracks
          .map((track) => track.id).toList(), [
        tracks[1].id, tracks[0].id,
      ]);

      // Remove the first track on A; B's next cloud read loses that item.
      await phoneA.removeTrack(userId, playlistId, tracks[1].id);
      expect(await phoneA.syncOwner(
        userId, apiA, ownerStillActive: () => true,
      ), isTrue);
      await phoneB.mergeRemote(userId, await apiSecond.playlists());
      expect((await phoneB.load(userId)).single.tracks
          .map((track) => track.id).toList(), [tracks[0].id]);

      await phoneA.delete(userId, playlistId);
      expect(await phoneA.syncOwner(
        userId, apiA, ownerStillActive: () => true,
      ), isTrue);
      await phoneB.mergeRemote(userId, await apiSecond.playlists());
      expect(await phoneB.load(userId), isEmpty);
    } finally {
      for (final account in accounts.reversed) {
        await account.cleanup();
      }
      await root.delete(recursive: true);
    }
  });
}
