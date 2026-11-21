import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../widgets/bz_brand_icons.dart';
import '../downloads/downloads_screen.dart';
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
  String _selected = 'Songs';
  List<FavoriteTrack> _favorites = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final favorites = await ref.read(favoritesStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _loading = false;
    });
  }

  List<TrackInfo> _queue() => [
        for (final f in _favorites) f.toTrackInfo(),
      ];

  void _playAll() {
    if (_favorites.isEmpty) return;
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: _favorites.first.id,
          queue: _queue(),
          origin: 'library',
          sourceContext: 'Songs',
        );
  }

  void _playOne(int index) {
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: _favorites[index].id,
          queue: _queue(),
          startIndex: index,
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
                TextButton(
                  onPressed: _editSections,
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final section = sections[index];
                final active = section == _selected;
                return ChoiceChip(
                  label: Text(section),
                  selected: active,
                  onSelected: (_) => setState(() => _selected = section),
                  selectedColor: theme.bzSurface2,
                  side: BorderSide(
                    color: active ? theme.bzAccent : theme.bzSeparator,
                  ),
                  labelStyle: TextStyle(
                    color: active ? theme.bzText1 : theme.bzText2,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                  showCheckmark: false,
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
                    : _buildEmptySection(theme, _selected),
          ),
        ],
      ),
    );
  }

  Widget _buildSongs(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 150),
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
                    'assets/icons/star.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFFE0A52B),
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: () async {
                    await ref.read(favoritesStoreProvider).toggle(fav);
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
