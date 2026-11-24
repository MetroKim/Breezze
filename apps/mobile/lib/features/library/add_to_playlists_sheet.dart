import 'package:material_ui/material_ui.dart';

import '../../app/bootstrap.dart' show FavoriteTrack;
import '../../app/playlist_store.dart';
import '../../widgets/bz_brand_icons.dart';

/// A shared, accessible multi-select surface for Search and Library.
/// Already-added songs are shown but cannot be selected again.
Future<Set<String>?> showMultiPlaylistPicker({
  required BuildContext context,
  required List<UserPlaylist> initialPlaylists,
  required String trackId,
  required Future<UserPlaylist?> Function() createPlaylist,
}) async {
  final playlists = List<UserPlaylist>.from(initialPlaylists);
  final selected = <String>{};
  var creating = false;

  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 6),
                child: Text('Add to Playlists',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text('Choose one or more playlists. Changes are saved offline.'),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (playlists.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No playlists yet. Create your first one below.'),
                      ),
                    for (final playlist in playlists)
                      CheckboxListTile(
                        key: ValueKey('playlist-choice-${playlist.id}'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18),
                        title: Text(playlist.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          playlist.tracks.any((song) => song.id == trackId)
                              ? 'Already added'
                              : '${playlist.tracks.length} songs',
                        ),
                        value: playlist.tracks.any((song) => song.id == trackId) ||
                            selected.contains(playlist.id),
                        onChanged: playlist.tracks.any((song) => song.id == trackId)
                            ? null
                            : (checked) => setSheetState(() {
                                  if (checked == true) {
                                    selected.add(playlist.id);
                                  } else {
                                    selected.remove(playlist.id);
                                  }
                                }),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const BzSvgIcon(name: 'plus', size: 20),
                title: const Text('New Playlist'),
                enabled: !creating,
                onTap: creating
                    ? null
                    : () async {
                        setSheetState(() => creating = true);
                        try {
                          final created = await createPlaylist();
                          if (!context.mounted) return;
                          if (created != null) {
                            setSheetState(() {
                              playlists.insert(0, created);
                              selected.add(created.id);
                            });
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text(
                                'Could not create playlist. Try again.',
                              )),
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            setSheetState(() => creating = false);
                          }
                        }
                      },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: creating || selected.isEmpty
                            ? null
                            : () => Navigator.of(context)
                                .pop(Set<String>.from(selected)),
                        child: Text(selected.length == 1
                            ? 'Add to 1 playlist'
                            : 'Add to ${selected.length} playlists'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Runs the common picker and commits membership changes in one atomic
/// owner-scoped playlist store update. Null means cancelled or session changed.
Future<int?> addSongToMultiplePlaylists({
  required BuildContext context,
  required PlaylistStore store,
  required String ownerId,
  required FavoriteTrack track,
  required bool Function() ownerStillActive,
  required Future<String?> Function() requestPlaylistName,
}) async {
  final playlists = await store.load(ownerId);
  if (!ownerStillActive()) return null;
  final selected = await showMultiPlaylistPicker(
    context: context,
    initialPlaylists: playlists,
    trackId: track.id,
    createPlaylist: () async {
      if (!ownerStillActive()) return null;
      final name = await requestPlaylistName();
      if (name == null || name.trim().isEmpty || !ownerStillActive()) {
        return null;
      }
      final id = await store.create(ownerId, name);
      if (!ownerStillActive()) return null;
      final updated = await store.load(ownerId);
      for (final playlist in updated) {
        if (playlist.id == id) return playlist;
      }
      return null;
    },
  );
  if (selected == null || !ownerStillActive()) return null;
  return store.addTrackToMany(ownerId, selected, track);
}
