import 'package:breezze/app/bootstrap.dart' show FavoriteTrack;
import 'package:breezze/app/playlist_store.dart';
import 'package:breezze/features/library/add_to_playlists_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserPlaylist playlist(String id, String name, {
    List<FavoriteTrack> tracks = const [],
  }) => UserPlaylist(
        id: id,
        name: name,
        createdAt: DateTime.utc(2026),
        tracks: tracks,
      );

  testWidgets('select multiple playlists; already-saved membership disabled',
      (tester) async {
    Set<String>? result;
    const favorite = FavoriteTrack(
      id: 'song-1', title: 'Song', artist: 'Artist',
    );
    final rows = [
      playlist('first', 'First mix'),
      playlist('second', 'Second mix'),
      playlist('already', 'Saved mix', tracks: [favorite]),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showMultiPlaylistPicker(
                context: context,
                initialPlaylists: rows,
                trackId: favorite.id,
                createPlaylist: () async => null,
              );
            },
            child: const Text('Open picker'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Playlists'), findsOneWidget);
    expect(find.text('Already added'), findsOneWidget);
    final already = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('playlist-choice-already')),
    );
    expect(already.value, isTrue);
    expect(already.onChanged, isNull);

    await tester.tap(find.text('First mix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second mix'));
    await tester.pumpAndSettle();
    expect(find.text('Add to 2 playlists'), findsOneWidget);
    await tester.tap(find.text('Add to 2 playlists'));
    await tester.pumpAndSettle();
    expect(result, {'first', 'second'});
  });

  testWidgets('new playlist is immediately selected for one-step addition',
      (tester) async {
    Set<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showMultiPlaylistPicker(
                context: context,
                initialPlaylists: const [],
                trackId: 'song-1',
                createPlaylist: () async =>
                    playlist('new', 'Created playlist'),
              );
            },
            child: const Text('Open picker'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('No playlists yet. Create your first one below.'),
        findsOneWidget);
    await tester.tap(find.text('New Playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Created playlist'), findsOneWidget);
    await tester.tap(find.text('Add to 1 playlist'));
    await tester.pumpAndSettle();
    expect(result, {'new'});
  });
}
