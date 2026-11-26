import 'dart:async';

import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/browse/browse_screen.dart';
import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _BrowseSource implements ProviderAdapter {
  final calls = <String>[];
  final requests = <Completer<ProviderOp<List<ProviderTrack>>>>[];

  @override
  String get providerId => 'browse-acceptance';

  @override
  String get adapterVersion => '1';

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) {
    calls.add(query);
    final pending = Completer<ProviderOp<List<ProviderTrack>>>();
    requests.add(pending);
    return pending.future;
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async =>
      ProviderUnsupported('Not used in Browse tests');
}

ProviderOp<List<ProviderTrack>> _tracks(String title, {String id = 'bz:youtube_music:abcdefghijk'}) =>
    ProviderOk([
      ProviderTrack(
        breezzeTrackId: id,
        providerTrackId: 'abcdefghijk',
        title: title,
        artist: 'Browse QA',
        duration: const Duration(minutes: 3),
      ),
    ]);

class _BrowseChartApi extends BreezzeApi {
  _BrowseChartApi() : super(baseUrl: 'https://breezze.example.test');

  @override
  Future<Map<String, dynamic>> discoveryMusicVideos({
    String query = 'official music video',
  }) async => {
        'source': 'YouTube Music via ytmusicapi',
        'items': [
          {
            'id': 'invalid_video_id',
            'title': 'Video with invalid ID',
            'artist': 'Browse QA',
            'playback': 'external_youtube_only',
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> discoveryDailyTop100({String country = 'us'}) async => {
        'source': 'Deezer',
        'title': 'Deezer Global Top Tracks (not a daily regional Top 100)',
        'territory': 'GLOBAL',
        'fetchedAt': '2026-11-24T12:00:00Z',
        'dailyTop100Available': false,
        'items': [
          {
            'id': '123456',
            'title': 'Verified metadata result',
            'artist': 'Catalog artist',
            'rank': 1,
            'playback': 'external_catalog_only',
          },
        ],
      };
}

class _BrowseSession extends AuthSessionController {
  _BrowseSession(this.catalogApi);

  final BreezzeApi catalogApi;

  @override
  AuthState build() => const AuthSignedOut();

  @override
  BreezzeApi get api => catalogApi;
}

Widget _browseApp(_BrowseSource source, {BreezzeApi? api}) => ProviderScope(
      overrides: [
        catalogSourceProvider.overrideWithValue(source),
        if (api != null)
          authSessionProvider.overrideWith(() => _BrowseSession(api)),
      ],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const Scaffold(body: BrowseScreen()),
      ),
    );

Future<void> _mountBrowse(
  WidgetTester tester,
  _BrowseSource source, {
  BreezzeApi? api,
}) async {
  // Browse uses a long CustomScrollView with lazy slivers. The default
  // 800x600 viewport does not build the genre results below the grid.
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_browseApp(source, api: api));
  await tester.pump();
}

void main() {
  testWidgets('Browse genre switching ignores older provider responses',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source);
    expect(source.calls, ['Afrobeats music']);

    await tester.tap(find.text('Bongo Flava'));
    await tester.pump();
    expect(source.calls, ['Afrobeats music', 'Bongo Flava music']);

    source.requests[1].complete(_tracks('Current genre song'));
    await tester.pump();
    expect(find.text('Current genre song'), findsOneWidget);

    source.requests[0].complete(_tracks('Stale genre song'));
    await tester.pump();
    expect(find.text('Current genre song'), findsOneWidget);
    expect(find.text('Stale genre song'), findsNothing);
  });

  testWidgets('Browse error state retries the selected genre successfully',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source);

    source.requests[0].complete(ProviderError('Temporary provider error'));
    await tester.pump();
    expect(find.text('Music is unavailable'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(source.calls, ['Afrobeats music', 'Afrobeats music']);
    source.requests[1].complete(_tracks('Recovered Browse song'));
    await tester.pump();
    expect(find.text('Recovered Browse song'), findsOneWidget);
    expect(find.text('Music is unavailable'), findsNothing);
  });

  testWidgets('Browse refuses native playback or downloads for catalog-only tracks',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source);

    source.requests[0].complete(
      _tracks('Metadata only', id: 'bz:apple_catalog:123456'),
    );
    await tester.pump();

    final downloadButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Download'),
        matching: find.byType(IconButton),
      ),
    );
    expect(downloadButton.onPressed, isNull);

    await tester.tap(find.text('Metadata only'));
    await tester.pump();
    expect(
      find.textContaining('Native playback is not available'),
      findsOneWidget,
    );
  });

  testWidgets('Browse labels the Deezer global chart fallback, not Daily Top 100',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source, api: _BrowseChartApi());
    source.requests[0].complete(ProviderOk(<ProviderTrack>[]));
    await tester.pump();

    await tester.ensureVisible(find.text('Daily Top 100'));
    await tester.tap(find.text('Daily Top 100'));
    await tester.pumpAndSettle();

    expect(find.text('Verified metadata result'), findsOneWidget);
    expect(
      find.textContaining('Deezer global ranking'),
      findsOneWidget,
    );
    expect(find.textContaining('Catalog metadata only'), findsOneWidget);
    expect(find.textContaining('Deezer'), findsWidgets);
  });
  testWidgets('Browse opens in-app Spotify and Deezer search while YouTube stays video-only',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source);
    source.requests[0].complete(ProviderOk(<ProviderTrack>[]));
    await tester.pump();

    await tester.ensureVisible(find.text('Music'));
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('YouTube Music'), findsNothing);
    expect(find.widgetWithText(BzFilterPill, 'Music Videos'), findsOneWidget);
  });

  testWidgets('Unavailable Browse sections do not invent charts',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source);
    source.requests[0].complete(ProviderOk(<ProviderTrack>[]));
    await tester.pump();

    await tester.ensureVisible(find.text('Trending Songs'));
    await tester.tap(find.text('Trending Songs'));
    await tester.pumpAndSettle();

    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.textContaining('Search results cannot be used as rankings'),
        findsOneWidget);
    expect(find.text('Back to Browse'), findsOneWidget);
  });

  testWidgets('Browse does not launch malformed external music-video IDs',
      (tester) async {
    final source = _BrowseSource();
    await _mountBrowse(tester, source, api: _BrowseChartApi());
    source.requests[0].complete(ProviderOk(<ProviderTrack>[]));
    await tester.pump();

    await tester.ensureVisible(find.text('Music Videos'));
    await tester.tap(find.text('Music Videos'));
    await tester.pumpAndSettle();

    expect(find.text('Video with invalid ID'), findsOneWidget);
    await tester.tap(find.byTooltip('Watch official video'));
    await tester.pump();
    expect(find.text('This video has no valid YouTube playback ID.'),
        findsOneWidget);
  });


}
