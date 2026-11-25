import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/browse/ytmusic_client_screen.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ClientApi extends BreezzeApi {
  _ClientApi() : super(baseUrl: 'https://breezze.test');

  bool unavailable = false;
  int exploreCalls = 0;
  int moodCalls = 0;
  int playlistCalls = 0;
  int artistSearchCalls = 0;
  int artistDetailCalls = 0;
  int chartsCalls = 0;
  bool accountAvailable = true;
  bool accountConnected = true;
  int accountPlaylistCalls = 0;
  int accountItemCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<Map<String, dynamic>> youtubeAccountStatus() async => {
    'available': accountAvailable,
    'connected': accountConnected,
    if (accountConnected) 'channelTitle': 'My YouTube Channel',
  };

  @override
  Future<Map<String, dynamic>> youtubeAccountPlaylists() async {
    accountPlaylistCalls++;
    return {
      'source': 'youtube_data_api',
      'scope': 'read_only_youtube_playlists',
      'items': [
        {'playlistId': 'OLAK5uy_abcdefghij', 'title': 'My Saved Playlist'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> youtubeAccountPlaylistItems(String playlistId) async {
    expect(playlistId, 'OLAK5uy_abcdefghij');
    accountItemCalls++;
    return {
      'source': 'youtube_data_api',
      'playlistId': playlistId,
      'hasMore': false,
      'items': [
        {'videoId': 'abcdefghijk', 'title': 'Connected Playlist Song',
          'artist': 'Connected Artist', 'playback': 'visible_youtube_only'},
        {'videoId': 'invalid', 'title': 'Invalid Item',
          'artist': 'Untrusted'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> youtubeAccountDisconnect() async {
    disconnectCalls++;
    accountConnected = false;
    return {'disconnected': true};
  }


  Map<String, dynamic> _ok(Map<String, dynamic> value) =>
      {'kind': 'ok', 'value': {'source': 'youtube_music', ...value}};

  @override
  Future<Map<String, dynamic>> ytMusicExplore() async {
    exploreCalls++;
    if (unavailable) throw StateError('catalog down');
    return _ok({
      'newReleases': [
        {'albumId': 'MPREabcdefghij', 'title': 'Featured Album',
          'artists': ['Example Artist']},
      ],
      'trending': [
        {'providerTrackId': 'abcdefghijk', 'title': 'Trending Song',
          'artist': 'Example Artist'},
      ],
      'newVideos': [
        {'videoId': 'invalid', 'title': 'Unavailable Video',
          'artist': 'Example Artist'},
        {'videoId': 'bcdefghijkl', 'title': 'Official Video',
          'artist': 'Example Artist'},
      ],
      'topSongsAvailable': false,
      'playbackAvailable': false,
    });
  }


  @override
  Future<Map<String, dynamic>> ytMusicSearchArtists(String query) async {
    artistSearchCalls++;
    expect(query, 'Example');
    return _ok({'artists': [
      {'artistId': 'UCabcdefghij123456', 'name': 'Example Artist'},
      {'artistId': 'invalid', 'name': 'Invalid Artist'},
    ]});
  }

  @override
  Future<Map<String, dynamic>> ytMusicArtist(String artistId) async {
    artistDetailCalls++;
    expect(artistId, 'UCabcdefghij123456');
    return _ok({'artist': {
      'artistId': artistId, 'name': 'Example Artist',
      'description': 'Public artist profile',
      'topSongs': [
        {'providerTrackId': 'efghijklmno', 'title': 'Artist Song'},
        {'providerTrackId': 'invalid', 'title': 'Invalid Song'},
      ],
      'albums': [{'browseId': 'MPREabcdefghij', 'title': 'Artist Album'}],
    }});
  }

  @override
  Future<Map<String, dynamic>> ytMusicCharts({String country = 'ZZ'}) async {
    chartsCalls++;
    expect(country, 'ZZ');
    return _ok({
      'country': 'ZZ', 'songRankingAvailable': false,
      'artists': [{'artistId': 'UCabcdefghij123456', 'name': 'Chart Artist'}],
      'musicVideoPlaylists': [
        {'playlistId': 'OLAK5uy_abcdefghij', 'title': 'Video Chart Playlist'},
      ],
    });
  }

  @override
  Future<Map<String, dynamic>> ytMusicMoods() async {
    moodCalls++;
    if (unavailable) throw StateError('moods down');
    return _ok({
      'sections': [
        {'title': 'Moods', 'categories': [
          {'title': 'Focus', 'params': 'ABCDEFGHIJ'},
        ]},
      ],
    });
  }

  @override
  Future<Map<String, dynamic>> ytMusicMoodPlaylists(String params, {int limit = 20}) async {
    expect(params, 'ABCDEFGHIJ');
    return _ok({
      'playlists': [
        {'playlistId': 'OLAK5uy_abcdefghij',
          'title': 'Focus Playlist'},
      ],
    });
  }

  @override
  Future<Map<String, dynamic>> ytMusicPlaylist(String playlistId, {int limit = 50}) async {
    playlistCalls++;
    expect(playlistId, 'OLAK5uy_abcdefghij');
    return _ok({
      'playbackAvailable': false,
      'playlist': {
        'title': 'Focus Playlist',
        'tracks': [
          {'providerTrackId': 'cdefghijklm',
            'title': 'Playlist Song', 'artist': 'Example Artist'},
        ],
      },
    });
  }

  @override
  Future<Map<String, dynamic>> ytMusicAlbum(String albumId) async {
    expect(albumId, 'MPREabcdefghij');
    return _ok({
      'playbackAvailable': false,
      'album': {
        'title': 'Featured Album',
        'tracks': [
          {'providerTrackId': 'defghijklmn',
            'title': 'Album Song', 'artist': 'Example Artist'},
        ],
      },
    });
  }
}

class _ClientSession extends AuthSessionController {
  _ClientSession(this.client);
  final BreezzeApi client;

  @override
  AuthState build() => const AuthSignedOut();

  @override
  BreezzeApi get api => client;
}

class _LinkedClientSession extends AuthSessionController {
  _LinkedClientSession(this.client);
  final BreezzeApi client;

  @override
  AuthState build() => const AuthSignedIn(
    userId: 'signed-in-breezze-user', email: 'test@example.test',
  );

  @override
  BreezzeApi get api => client;
}

Future<void> _mount(WidgetTester tester, _ClientApi api,
    {bool signedIn = false}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => signedIn
            ? _LinkedClientSession(api) : _ClientSession(api)),
      ],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const YouTubeMusicClientScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('YouTube Music companion loads real public catalog sections',
      (tester) async {
    final api = _ClientApi();
    await _mount(tester, api);

    expect(find.text('Explore YouTube Music'), findsOneWidget);
    expect(find.text('New releases'), findsOneWidget);
    expect(find.text('Featured Album'), findsOneWidget);
    expect(find.text('Trending Song'), findsOneWidget);
    expect(find.text('Official Video'), findsOneWidget);
    expect(find.text('Moods & activities'), findsOneWidget);
    expect(find.textContaining('personal YouTube Music library is not connected'),
        findsOneWidget);
    expect(api.exploreCalls, 1);
    expect(api.moodCalls, 1);

    final invalid = find.ancestor(
      of: find.text('Unavailable Video'),
      matching: find.byType(ListTile),
    );
    final row = tester.widget<ListTile>(invalid);
    expect(row.onTap, isNull);
  });

  testWidgets('mood discovery opens public playlist tracks without native audio',
      (tester) async {
    final api = _ClientApi();
    await _mount(tester, api);
    await tester.ensureVisible(find.text('Focus'));
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    expect(find.text('Focus Playlist'), findsOneWidget);
    await tester.tap(find.text('Focus Playlist'));
    await tester.pumpAndSettle();

    expect(find.text('Playlist Song'), findsOneWidget);
    expect(find.textContaining('visible YouTube player'), findsOneWidget);
    expect(api.playlistCalls, 1);
  });

  testWidgets('album discovery opens a read-only tracklist', (tester) async {
    final api = _ClientApi();
    await _mount(tester, api);

    await tester.tap(find.text('Featured Album'));
    await tester.pumpAndSettle();
    expect(find.text('Album Song'), findsOneWidget);
    expect(find.textContaining('offline downloads are not available'),
        findsOneWidget);
  });

  testWidgets('signed-in listener sees separately authorized YouTube playlist',
      (tester) async {
    final api = _ClientApi();
    await _mount(tester, api, signedIn: true);

    expect(find.text('Your YouTube account'), findsOneWidget);
    expect(find.text('Connected: My YouTube Channel'), findsOneWidget);
    expect(find.text('Your YouTube playlists'), findsOneWidget);
    expect(find.text('My Saved Playlist'), findsOneWidget);
    expect(find.text('Connect YouTube'), findsNothing);
    expect(api.accountPlaylistCalls, 1);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect YouTube account?'), findsOneWidget);
    await tester.tap(find.text('Disconnect').last);
    await tester.pumpAndSettle();

    expect(api.disconnectCalls, 1);
    expect(find.text('My Saved Playlist'), findsNothing);
    expect(find.text('Connect YouTube'), findsOneWidget);
  });

  testWidgets('linked account playlist opens read-only video items in Breezze',
      (tester) async {
    final api = _ClientApi();
    await _mount(tester, api, signedIn: true);

    await tester.tap(find.text('My Saved Playlist'));
    await tester.pumpAndSettle();

    expect(find.text('Connected Playlist Song'), findsOneWidget);
    expect(find.textContaining('videos use the official YouTube player'),
        findsOneWidget);
    expect(api.accountItemCalls, 1);
    final invalid = find.ancestor(
      of: find.text('Invalid Item'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(invalid).onTap, isNull);
  });

  testWidgets('does not enable Google consent button without configured credentials',
      (tester) async {
    final api = _ClientApi()
      ..accountAvailable = false
      ..accountConnected = false;
    await _mount(tester, api, signedIn: true);

    expect(find.text('Account connection is not configured yet.'),
        findsOneWidget);
    final connect = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Connect YouTube'),
    );
    expect(connect.onPressed, isNull);
    expect(api.accountPlaylistCalls, 0);
  });

  testWidgets('full source outage displays honest retry rather than fake music',
      (tester) async {
    final api = _ClientApi()..unavailable = true;
    await _mount(tester, api);

    expect(find.text('YouTube Music catalog is unavailable'), findsOneWidget);
    expect(find.text('Featured Album'), findsNothing);

    api.unavailable = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Featured Album'), findsOneWidget);
  });

  testWidgets('artist search validates IDs and opens public artist albums',
      (tester) async {
    final api = _ClientApi();
    await _mount(tester, api);
    await tester.tap(find.text('Find artists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search artists'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an artist name'), findsOneWidget);
    expect(api.artistSearchCalls, 0);
    await tester.enterText(find.byType(TextField), 'Example');
    await tester.tap(find.text('Search artists'));
    await tester.pumpAndSettle();
    expect(api.artistSearchCalls, 1);
    final invalidArtist = find.ancestor(
      of: find.text('Invalid Artist'), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(invalidArtist).onTap, isNull);
    await tester.tap(find.text('Example Artist'));
    await tester.pumpAndSettle();
    expect(api.artistDetailCalls, 1);
    expect(find.text('Artist Song'), findsOneWidget);
    final invalidSong = find.ancestor(
      of: find.text('Invalid Song'), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(invalidSong).onTap, isNull);
    await tester.tap(find.text('Artist Album'));
    await tester.pumpAndSettle();
    expect(find.text('Album Song'), findsOneWidget);
  });

  testWidgets('charts do not fabricate a Top Songs ranking',
      (tester) async {
    final api = _ClientApi();
    await _mount(tester, api);
    await tester.tap(find.text('Music charts'));
    await tester.pumpAndSettle();
    expect(api.chartsCalls, 1);
    expect(find.text('Verified Top Songs rankings unavailable'), findsOneWidget);
    expect(find.text('Chart Artist'), findsOneWidget);
    await tester.tap(find.text('Video Chart Playlist'));
    await tester.pumpAndSettle();
    expect(api.playlistCalls, 1);
    expect(find.text('Playlist Song'), findsOneWidget);
  });

}
