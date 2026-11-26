import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/catalog/catalog_detail_screens.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const artistId = '0TnOYISbd1XYRBk9myaseg';
const albumId = '2up3OPMp9Tb4dAKM2erWXQ';
const trackId = '4iV5W9uYEdYUVa79Axb7Rh';

class _SpotifyApi extends BreezzeApi {
  _SpotifyApi() : super(baseUrl: 'https://breezze.test');
  int artistSearchCalls = 0;
  int profileCalls = 0;
  int albumCalls = 0;

  @override
  Future<Map<String, dynamic>> searchSpotifyArtists(String query) async {
    artistSearchCalls++;
    return { 'kind': 'ok', 'value': [
      {'id': artistId, 'name': 'Test Singer'},
    ] };
  }

  @override
  Future<Map<String, dynamic>> spotifyArtistPage(String id) async {
    profileCalls++;
    expect(id, artistId);
    return {'kind': 'ok', 'value': {
      'artist': {
        'id': artistId, 'name': 'Test Singer',
        'url': 'https://open.spotify.com/artist/$artistId',
        'genres': ['Afrobeats'], 'followers': 99,
      },
      'songs': [
        {
          'providerTrackId': trackId,
          'title': 'Spotify Song', 'artist': 'Test Singer',
          'durationSec': 210,
        },
      ],
      'albums': [
        {
          'id': albumId, 'title': 'New Studio Album',
          'releaseDate': '2026-09-02',
          'type': 'album', 'trackCount': 10,
          'url': 'https://open.spotify.com/album/$albumId',
        },
      ],
      'newReleases': [
        {
          'id': albumId, 'title': 'New Studio Album',
          'releaseDate': '2026-09-02', 'type': 'album',
        },
      ],
      'searchSuggestions': ['Test Singer Afrobeats'],
      'tours': {'status': 'unsupported', 'events': <Object>[]},
      'songStatus': 'ok', 'albumStatus': 'ok',
    }};
  }

  @override
  Future<Map<String, dynamic>> spotifyAlbumPage(String id) async {
    albumCalls++;
    expect(id, albumId);
    return {'kind': 'ok', 'value': {
      'album': {'id': albumId, 'title': 'New Studio Album',
        'releaseDate': '2026-09-02'},
      'tracks': [
        {'providerTrackId': trackId, 'title': 'Spotify Song', 'artist': 'Test Singer'},
      ],
      'tracksStatus': 'ok',
    }};
  }
}

class _SpotifySession extends AuthSessionController {
  _SpotifySession(this.artistApi);
  final BreezzeApi artistApi;

  @override
  AuthState build() => const AuthSignedIn(
      userId: 'artist-qa-user', email: 'artist@breezze.example');

  @override
  BreezzeApi get api => artistApi;
}

void main() {
  testWidgets('artist page uses Spotify only for songs, albums, releases and data',
      (tester) async {
    final api = _SpotifyApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [authSessionProvider.overrideWith(() => _SpotifySession(api))],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const ArtistDetailScreen(
          artist: 'Test Singer', spotifyArtistId: artistId,
          savedTracks: [],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.profileCalls, 1);
    expect(api.artistSearchCalls, 0,
        reason: 'Supplied Spotify ID skips ambiguous name-based fallback');
    expect(find.text('Test Singer'), findsWidgets);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Spotify Song'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('New Releases'), 220);
    expect(find.text('New Releases'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Albums & Singles'), 220);
    expect(find.text('Albums & Singles'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tours'), 220);
    expect(find.text('Tours'), findsOneWidget);
    expect(find.text('Deezer catalog discography'), findsNothing);
    await tester.scrollUntilVisible(find.text('Related Searches'), 220);
    expect(find.text('Test Singer Afrobeats'), findsOneWidget);
  });

  testWidgets('legacy saved artist resolves Spotify identity by exact name',
      (tester) async {
    final api = _SpotifyApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [authSessionProvider.overrideWith(() => _SpotifySession(api))],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const ArtistDetailScreen(
          artist: 'Test Singer', savedTracks: [],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.artistSearchCalls, 1);
    expect(api.profileCalls, 1);
    expect(find.text('Test Singer'), findsWidgets);
  });
}
