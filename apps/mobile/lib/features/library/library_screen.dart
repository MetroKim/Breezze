import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../core/audio/playback_source_policy.dart';
import '../../app/playlist_store.dart';
import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../widgets/bz_brand_icons.dart';
import '../downloads/downloads_screen.dart';
import 'playlist_detail_screen.dart';
import '../catalog/catalog_detail_screens.dart';
import '../player/player_controller.dart';

/// Library navigation follows the user's requested section order. Only
/// Songs/Favorites and Downloaded currently have live local data; the other
/// collection types remain honest empty states until their APIs are connected.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _allSections = [
    'Playlists',
    'Artists',
    'Albums',
    'Songs',
    'Genres',
    'Compilations',
  ];

  Set<String> _visibleSections = {'Playlists', 'Artists', 'Albums', 'Songs'};
  String _selected = 'Playlists';
  final _playlistStore = PlaylistStore();
  String _ownerId = 'guest';
  List<UserPlaylist> _playlists = [];
  List<FavoriteTrack> _favorites = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final auth = ref.read(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    final favorites = await ref.read(favoritesStoreProvider).load(ownerId: ownerId);
    var playlists = await _playlistStore.load(ownerId);
    if (auth is AuthSignedIn) {
      try {
        final remote = await ref.read(authSessionProvider.notifier).api.playlists();
        await _playlistStore.mergeRemote(ownerId, remote);
        playlists = await _playlistStore.load(ownerId);
      } catch (_) {
        // Local cache remains usable while offline; cloud changes sync next refresh.
      }
    }
    final currentAuth = ref.read(authSessionProvider);
    final currentOwnerId =
        currentAuth is AuthSignedIn ? currentAuth.userId : 'guest';
    if (!mounted || currentOwnerId != ownerId) return;
    setState(() {
      _ownerId = ownerId;
      _favorites = favorites;
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final auth = ref.read(authSessionProvider);
    String? remoteId;
    if (auth is AuthSignedIn) {
      try {
        final remote = await ref.read(authSessionProvider.notifier).api.createPlaylist(name.trim());
        remoteId = remote['id'] as String?;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playlist saved locally; account sync is unavailable.')),
          );
        }
      }
    }
    await _playlistStore.create(_ownerId, name, id: remoteId);
    if (!mounted) return;
    setState(() => _selected = 'Playlists');
    await _refresh();
  }

  void _openPlaylist(UserPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          ownerId: _ownerId,
          playlistId: playlist.id,
          onChanged: _refresh,
        ),
      ),
    );
  }

  List<TrackInfo> _queue() => [
        for (final f in _favorites)
          if (canQueueTrackId(f.id)) f.toTrackInfo(),
      ];

  Future<void> _playAll() async {
    if (_favorites.isEmpty) return;
    final nativeIndex = _favorites.indexWhere((item) => canQueueTrackId(item.id));
    if (nativeIndex >= 0) {
      if (_favorites.any((item) => !canQueueTrackId(item.id)) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogue-only tracks are excluded from native playback; only playable tracks enter the queue.')),
        );
      }
      await _playOne(nativeIndex);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved songs have an authorized playback source yet.')),
      );
    }
  }

  Future<void> _playOne(int index) async {
    final track = _favorites[index];
    if (!canQueueTrackId(track.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This saved item has metadata only; Breezze cannot play it from this source.')),
        );
      }
      return;
    }
    final queue = _queue();
    final queueIndex = queue.indexWhere((item) => item.id == track.id);
    if (queueIndex < 0) return;
    await ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.id,
          queue: queue,
          startIndex: queueIndex,
          origin: 'library',
          sourceContext: 'Songs',
        );
  }

  Future<void> _editSections() async {
    final draft = Set<String>.from(_visibleSections);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customize Library',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('Choose which sections appear in your Library.',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                for (final section in _allSections)
                  CheckboxListTile(
                    value: draft.contains(section),
                    title: Text(section),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) => setSheetState(() {
                      if (value == true) {
                        draft.add(section);
                      } else {
                        if (draft.length > 1) draft.remove(section);
                      }
                    }),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(draft),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      _visibleSections = result;
      if (_selected != 'Downloaded' && !_visibleSections.contains(_selected)) {
        _selected = _visibleSections.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authSessionProvider, (previous, next) => _refresh());
    ref.listen<int>(playlistRefreshSignalProvider, (previous, next) => _refresh());
    final theme = Theme.of(context);
    final sections = [..._allSections.where(_visibleSections.contains), 'Downloaded'];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Library', style: theme.textTheme.displayMedium),
                ),
                if (_selected == 'Playlists')
                  IconButton(
                    tooltip: 'Create playlist',
                    onPressed: _createPlaylist,
                    icon: BzSvgIcon(name: 'plus', color: theme.bzAccent),
                  ),
                TextButton(
                  onPressed: _editSections,
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
          // Capsule pill section selector — spec §2.3 tab indicators use
          // --radius-pill. Solid active fill, no outline chips: the Apple
          // Music Library filter treatment (quiet chrome, artwork forward).
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final section = sections[index];
                final active = section == _selected;
                return _LibraryPill(
                  label: section,
                  active: active,
                  onTap: () => setState(() => _selected = section),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _selected == 'Downloaded'
                ? const DownloadsScreen()
                : _selected == 'Songs'
                    ? _buildSongs(theme)
                    : _selected == 'Playlists'
                        ? _buildPlaylists(theme)
                        : _selected == 'Artists'
                            ? _buildArtists(theme)
                            : _buildEmptySection(theme, _selected),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylists(ThemeData theme) {
    if (_loading) return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => const BzSkeletonTrackRow(),
    );
    if (_playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BzBnoteMark(size: 58, color: theme.bzText2),
              const SizedBox(height: 16),
              Text('Create your first playlist',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Build collections of songs and keep them on this device.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.bzText2),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _createPlaylist,
                icon: BzSvgIcon(
                  name: 'plus',
                  color: theme.bzBackground,
                  size: 18,
                ),
                label: const Text('New Playlist'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(8, 4, 8, BzBreakpoints.bottomClearance(context, compact: 150)),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        final artwork = playlist.tracks
            .where((track) => track.artworkUrl != null)
            .map((track) => track.artworkUrl!)
            .toList();
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(BzRadius.artwork),
            child: artwork.isEmpty
                ? Container(
                    width: 54,
                    height: 54,
                    color: theme.bzSurface1,
                    alignment: Alignment.center,
                    child: BzBnoteMark(size: 28, color: theme.bzText2),
                  )
                : Image.network(
                    artwork.first,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        BzBnoteMark(size: 54, color: theme.bzText2),
                  ),
          ),
          title: Text(playlist.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${playlist.tracks.length} songs · On this device',
            style: TextStyle(color: theme.bzText2),
          ),
          trailing: BzSvgIcon(name: 'chevron-right', color: theme.bzText2),
          onTap: () => _openPlaylist(playlist),
        );
      },
    );
  }

  Widget _buildArtists(ThemeData theme) {
    if (_loading) return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => const BzSkeletonTrackRow(),
    );
    final grouped = <String, List<FavoriteTrack>>{};
    for (final track in _favorites) {
      grouped.putIfAbsent(track.artist.trim().isEmpty ? 'Unknown artist' : track.artist, () => []).add(track);
    }
    if (grouped.isEmpty) return _emptyState(theme, 'No artists yet', 'Save songs to build your artist library.');
    final artists = grouped.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 150),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final entry = artists[index];
        return ListTile(
          leading: CircleAvatar(backgroundColor: theme.bzSurface2, child: BzSvgIcon(name: 'mic', color: theme.bzText1)),
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} saved songs'),
          trailing: BzSvgIcon(name: 'chevron-right', color: theme.bzText2),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(
                artist: entry.key,
                savedTracks: entry.value,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongs(ThemeData theme) {
    if (_loading) return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => const BzSkeletonTrackRow(),
    );
    if (_favorites.isEmpty) {
      return _emptyState(
        theme,
        'No saved songs yet',
        'Star a track while listening and it will appear here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_favorites.length} saved songs',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: _playAll,
                icon: SvgPicture.asset(
                  'assets/icons/play.svg',
                  width: 15,
                  height: 15,
                  colorFilter: ColorFilter.mode(
                    theme.bzAccent,
                    BlendMode.srcIn,
                  ),
                ),
                label: const Text('Play all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(8, 0, 8, BzBreakpoints.bottomClearance(context, compact: 150)),
            itemCount: _favorites.length,
            itemBuilder: (context, i) {
              final fav = _favorites[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(BzRadius.artwork),
                  child: fav.artworkUrl != null
                      ? Image.network(
                          fav.artworkUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              BzBnoteMark(size: 50, color: theme.bzText2),
                        )
                      : BzBnoteMark(size: 50, color: theme.bzText2),
                ),
                title: Text(fav.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(fav.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _playOne(i),
                trailing: IconButton(
                  tooltip: 'Remove from favorites',
                  icon: SvgPicture.asset(
                    'assets/icons/star-filled.svg',
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      theme.bzWarning,
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: () async {
                    await ref.read(favoritesStoreProvider).toggle(fav, ownerId: _ownerId);
                    await ref.read(outboxSyncProvider).drainIfSignedIn();
                    _refresh();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySection(ThemeData theme, String section) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => const BzSkeletonTrackRow(),
      );
    }
    final detail = switch (section) {
      'Playlists' => 'Your created and saved playlists will appear here.',
      'Artists' => 'Artists you follow or save will appear here.',
      'Albums' => 'Albums added to your library will appear here.',
      'Genres' => 'Genres represented in your saved music will appear here.',
      'Compilations' => 'Compilation albums in your library will appear here.',
      _ => 'Your music collection will appear here.',
    };
    return _emptyState(theme, 'No $section yet', detail);
  }

  Widget _emptyState(ThemeData theme, String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BzBnoteMark(size: 58, color: theme.bzText2),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.bzText2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Library section pill — capsule (spec --radius-pill) with a solid
/// text1 fill when active, surface2 when not. 36pt visual height with
/// a generous hit area for the 44pt minimum.
class _LibraryPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LibraryPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: BzMotion.fastMs),
          curve: const Cubic(0.22, 1, 0.36, 1),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? theme.bzText1 : theme.bzSurface2,
            borderRadius: BorderRadius.circular(BzRadius.capsule),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: BzType.subheadline,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? theme.bzBackground : theme.bzText2,
            ),
          ),
        ),
      ),
    );
  }
}
