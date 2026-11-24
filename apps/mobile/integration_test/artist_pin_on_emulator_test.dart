import 'package:breezze/app/followed_artist_store.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/catalog/catalog_detail_screens.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// Isolated API simulator for native UI acceptance; live API/account
/// isolation is covered by the separate production playlist smoke workflow.
class _ArtistCloud {
  final byOwner = <String, Map<String, Map<String, dynamic>>>{};
}

class _ArtistApi extends BreezzeApi {
  _ArtistApi(this.cloud, this.ownerId)
      : super(baseUrl: 'https://breezze.example.test') {
    accessToken = 'qa-' + ownerId;
  }

  final _ArtistCloud cloud;
  final String ownerId;
  bool offline = false;

  Map<String, Map<String, dynamic>> get records =>
      cloud.byOwner.putIfAbsent(ownerId, () => {});

  void _checkOnline() {
    if (offline) throw StateError('Simulated offline connection');
  }

  @override
  Future<Map<String, dynamic>> getFollowedArtists() async {
    _checkOnline();
    return {
      'items': [
        for (final row in records.values) Map<String, dynamic>.from(row),
      ],
    };
  }

  @override
  Future<void> followArtist(
    String key, bool following, {String? displayName}
  ) async {
    _checkOnline();
    if (!following) {
      records.remove(key);
      return;
    }
    final current = records[key];
    records[key] = {
      'artistKey': key,
      'displayName': displayName ?? current?['displayName'] ?? key,
      'isPinned': current?['isPinned'] ?? false,
      'followedAt': current?['followedAt'] ??
          DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<void> pinArtist(String key, bool pinned) async {
    _checkOnline();
    final record = records[key];
    if (record == null) throw StateError('Artist is not followed');
    record['isPinned'] = pinned;
  }

  @override
  Future<Map<String, dynamic>> discoveryArtistSearch(String query) async =>
      {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> discoveryMusicVideos({
    String query = 'official music video',
  }) async => {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> discoveryConcerts({
    String country = 'TZ',
    String? city,
  }) async => {'items': <Map<String, dynamic>>[]};
}

class _CurrentApi {
  _CurrentApi(this.value);
  _ArtistApi value;
}

class _SignedInArtistSession extends AuthSessionController {
  _SignedInArtistSession(this.currentApi, this.ownerId);

  final _CurrentApi currentApi;
  final String ownerId;

  @override
  AuthState build() => AuthSignedIn(
        userId: ownerId,
        email: ownerId + '@example.test',
      );

  @override
  BreezzeApi get api => currentApi.value;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native artist UI persists offline pins and isolates accounts',
      (tester) async {
    // Per-test owner and artist identifiers prevent cross-test contamination.
    final seed = DateTime.now().microsecondsSinceEpoch.toString();
    final ownerA = 'artist-ui-a-' + seed;
    final ownerB = 'artist-ui-b-' + seed;
    final artistId = 'native_qa_' + seed;
    final artistKey = 'catalog:' + artistId;
    const artistName = 'Breezze Native QA Artist';

    final cloud = _ArtistCloud();
    final apiA = _ArtistApi(cloud, ownerA);
    final secondSession = _ArtistApi(cloud, ownerA);
    final apiB = _ArtistApi(cloud, ownerB);
    final current = _CurrentApi(apiA);
    final storage = const FlutterSecureStorage();

    Future<void> waitForLabel(String label) async {
      for (var attempt = 0; attempt < 80; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text(label).evaluate().isNotEmpty) return;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Artist screen never displayed ' + label);
    }

    Future<void> waitForSyncedOutbox(String ownerId) async {
      for (var attempt = 0; attempt < 80; attempt++) {
        if (await FollowedArtistStore().pendingCount(ownerId) == 0) return;
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      fail('Followed artist outbox did not drain');
    }

    Future<void> mountArtist(String ownerId) async {
      // Reconstruct the real artist page and Riverpod scope, but keep
      // Keychain/Keystore-backed persistence between screen instances.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _SignedInArtistSession(current, ownerId),
          ),
        ],
        child: MaterialApp(
          theme: bzLightTheme(),
          home: ArtistDetailScreen(
            artist: artistName,
            canonicalArtistId: artistId,
            savedTracks: const [],
          ),
        ),
      ));
    }

    try {
      await mountArtist(ownerA);
      await waitForLabel('Follow');
      await tester.tap(find.text('Follow'));
      await waitForLabel('Following');
      expect((await FollowedArtistStore().find(ownerA, artistKey))?.isPinned,
          isFalse);

      // The real Pin button queues its change while the API is offline.
      apiA.offline = true;
      await tester.tap(find.text('Pin'));
      await waitForLabel('Unpin');
      expect((await FollowedArtistStore().find(ownerA, artistKey))?.isPinned,
          isTrue);
      expect(await FollowedArtistStore().pendingCount(ownerA), 1);

      // Recreate the entire widget tree: the native device still shows Unpin.
      await mountArtist(ownerA);
      await waitForLabel('Unpin');
      expect((await FollowedArtistStore().find(ownerA, artistKey))?.isPinned,
          isTrue);

      apiA.offline = false;
      await mountArtist(ownerA);
      await waitForLabel('Unpin');
      await waitForSyncedOutbox(ownerA);
      expect((await secondSession.getFollowedArtists())['items'],
          contains(predicate<Map>((row) =>
              row['artistKey'] == artistKey && row['isPinned'] == true)));

      // A different account cannot view or change A's follow/pin state.
      expect((await apiB.getFollowedArtists())['items'], isEmpty);
      current.value = apiB;
      await mountArtist(ownerB);
      await waitForLabel('Follow');
      expect(await FollowedArtistStore().find(ownerB, artistKey), isNull);

      current.value = apiA;
      await mountArtist(ownerA);
      await waitForLabel('Unpin');
      await tester.tap(find.text('Unpin'));
      await waitForLabel('Pin');
      await waitForSyncedOutbox(ownerA);
      expect((cloud.byOwner[ownerA]?[artistKey])?['isPinned'], isFalse);

      await tester.tap(find.text('Following'));
      await waitForLabel('Follow');
      await waitForSyncedOutbox(ownerA);
      expect((await secondSession.getFollowedArtists())['items'], isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // Clear only this test's owner-scoped data, never another account.
      for (final owner in [ownerA, ownerB]) {
        final key = Uri.encodeComponent(owner);
        await storage.delete(key: 'breezze:followed_artists:v1:' + key);
        await storage.delete(
          key: 'breezze:followed_artists:pending:v1:' + key,
        );
      }
    }
  });
}
