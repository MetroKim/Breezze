import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../app/downloads_controller.dart';
import '../../app/search_history_store.dart';
import '../../app/playlist_store.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../player/player_controller.dart';

/// Search screen — real results from the live source, with local recent
/// searches and live download progress.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _history = SearchHistoryStore();
  List<BzTrack> _results = [];
  List<String> _recentSearches = [];
  var _loading = false;
  var _searched = false;
  var _searchLibrary = false;
  String? _error;

  static const _suggestedSearches = <String, String>{
    'Latest Songs': 'new songs',
    'New Releases': 'new music releases',
    'Trending Songs': 'trending songs',
    'Daily Top 100': 'top 100 songs',
    'Coming Soon': 'upcoming albums',
    'Music Videos': 'music videos',
    'Charts': 'top music charts',
    'Browse by Genre': 'Afrobeats',
    'Moods & Activities': 'workout music',
    'Concerts': 'upcoming concerts',
    'City Charts': 'top city charts',
  };
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _history.load();
      if (!mounted) return;
      setState(() => _recentSearches = history);
    } catch (_) {
      // Search must remain usable when local history storage is unavailable.
    }
  }

  Future<void> _search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;

    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
    });

    // Search history is best-effort local UI state. A disk failure must not
    // prevent the actual catalogue search or masquerade as a provider outage.
    try {
      final history = await _history.add(normalized);
      if (mounted && generation == _searchGeneration) {
        setState(() => _recentSearches = history);
      }
    } catch (_) {
      // Continue with the music-source request even if persistence fails.
    }

    if (_searchLibrary) {
      try {
        final favorites = await ref.read(favoritesStoreProvider).load();
        if (!mounted || generation != _searchGeneration) return;
        final needle = normalized.toLowerCase();
        final matches = favorites.where((item) =>
            item.title.toLowerCase().contains(needle) ||
            item.artist.toLowerCase().contains(needle));
        setState(() {
          _loading = false;
          _results = [
            for (final item in matches)
              BzTrack(
                id: item.id,
                title: item.title,
                artist: item.artist,
                artworkUrl: item.artworkUrl,
                duration: Duration(milliseconds: item.durationMs),
              ),
          ];
        });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _loading = false;
          _results = [];
          _error = 'Your library could not be searched right now.';
        });
      }
      return;
    }

    try {
      final op = await ref.read(youtubeSourceProvider).search(normalized);
      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _loading = false;
        _results = op is ProviderOk<List<ProviderTrack>>
            ? op.value
                .map((track) => BzTrack(
                      id: track.breezzeTrackId,
                      title: track.title,
                      artist: track.artist,
                      artworkUrl: track.artworkUrl,
                      duration: track.duration,
                    ))
                .toList()
            : [];
        if (op is! ProviderOk<List<ProviderTrack>>) {
          _error = 'Search could not be completed. Try again in a moment.';
        }
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _results = [];
        _error = 'Could not reach the music source. Check your connection.';
      });
    }
  }

  Future<void> _removeHistory(String query) async {
    final history = await _history.remove(query);
    if (!mounted) return;
    setState(() => _recentSearches = history);
  }

  Future<void> _clearHistory() async {
    await _history.clear();
    if (!mounted) return;
    setState(() => _recentSearches = []);
  }

  void _reuseSearch(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _search(query);
  }

  Future<String?> _requestPlaylistName() async {
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
    return name?.trim().isEmpty == true ? null : name?.trim();
  }

  Future<void> _showAddToPlaylist(BzTrack track) async {
    final auth = ref.read(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    final store = PlaylistStore();
    var playlists = await store.load(ownerId);
    String? selectedId;

    Future<String?> create(String name) async {
      String? remoteId;
      if (auth is AuthSignedIn) {
        try {
          final remote = await ref.read(authSessionProvider.notifier).api.createPlaylist(name);
          remoteId = remote['id'] as String?;
        } catch (_) {}
      }
      await store.create(ownerId, name, id: remoteId);
      return remoteId;
    }

    if (playlists.isEmpty) {
      final name = await _requestPlaylistName();
      if (name == null || name.isEmpty) return;
      await create(name);
      playlists = await store.load(ownerId);
      if (playlists.isNotEmpty) selectedId = playlists.first.id;
    } else {
      selectedId = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text('Add to Playlist', style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final playlist in playlists)
                ListTile(
                  leading: BzBnoteMark(size: 40, color: Theme.of(context).bzText2),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.tracks.length} songs'),
                  onTap: () => Navigator.of(context).pop(playlist.id),
                ),
              ListTile(
                leading: BzSvgIcon(name: 'plus', color: Theme.of(context).bzAccent),
                title: const Text('New Playlist'),
                onTap: () => Navigator.of(context).pop('__new__'),
              ),
            ],
          ),
        ),
      );
      if (selectedId == '__new__') {
        final name = await _requestPlaylistName();
        if (name == null || name.isEmpty) return;
        await create(name);
        playlists = await store.load(ownerId);
        selectedId = playlists.isEmpty ? null : playlists.first.id;
      }
    }

    if (selectedId == null) return;
    final remotePlaylist = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(selectedId);
    if (auth is AuthSignedIn && remotePlaylist) {
      try {
        await ref.read(authSessionProvider.notifier).api.addPlaylistTrack(selectedId, track.id);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not sync this song to your playlist.')));
        return;
      }
    }
    await store.addTrack(ownerId, selectedId, FavoriteTrack(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.duration.inMilliseconds,
    ));
    if (!mounted) return;
    ref.read(playlistRefreshSignalProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to playlist')));
  }

  Future<void> _addFavorite(BzTrack track) async {
    final favorites = ref.read(favoritesStoreProvider);
    if (!await favorites.isFavorite(track.id)) {
      await favorites.toggle(
        FavoriteTrack(
          id: track.id,
          title: track.title,
          artist: track.artist,
          artworkUrl: track.artworkUrl,
          durationMs: track.duration.inMilliseconds,
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Library updated')),
    );
  }

  void _download(BzTrack track) {
    ref.read(downloadProgressProvider.notifier).download(track);
  }

  void _play(BzTrack track) {
    final queue = [
      for (final item in _results)
        TrackInfo(
          id: item.id,
          title: item.title,
          artist: item.artist,
          artworkUrl: item.artworkUrl,
          duration: item.duration,
        )
    ];
    final index = _results.indexOf(track);
    if (queue.isEmpty) return;
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.id,
          queue: queue,
          startIndex: index.clamp(0, queue.length - 1),
          origin: 'search',
          sourceContext: 'Search',
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ref.watch(downloadProgressProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Search', style: theme.textTheme.displayMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  onSubmitted: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Songs, artists and more',
                    prefixIcon: BzSvgIcon(name: 'search', color: theme.bzText2),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: BzSvgIcon(name: 'close', color: theme.bzText2),
                            onPressed: () {
                              _searchGeneration++;
                              _controller.clear();
                              setState(() {
                                _loading = false;
                                _searched = false;
                                _results = [];
                                _error = null;
                              });
                            },
                          ),
                    filled: true,
                    fillColor: theme.bzSurface1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BzRadius.input),
                      borderSide: BorderSide(color: theme.bzSeparator),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BzRadius.input),
                      borderSide: BorderSide(color: theme.bzSeparator),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Breezze'),
                      selected: !_searchLibrary,
                      onSelected: (_) {
                        setState(() => _searchLibrary = false);
                        if (_controller.text.trim().isNotEmpty) {
                          _search(_controller.text);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Your Library'),
                      selected: _searchLibrary,
                      onSelected: (_) {
                        setState(() => _searchLibrary = true);
                        if (_controller.text.trim().isNotEmpty) {
                          _search(_controller.text);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? _buildRecentSearches(theme)
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Text(
                                  'No results for "${_controller.text.trim()}"',
                                  style: theme.textTheme.titleMedium,
                                ),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 8, 0, 220),
                                itemCount: _results.length,
                                itemBuilder: (context, index) {
                                  final track = _results[index];
                                  final value = progress[track.id];
                                  return ListTile(
                                    leading: track.artworkUrl != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    BzRadius.artwork),
                                            child: Image.network(
                                              track.artworkUrl!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  BzBnoteMark(
                                                size: 48,
                                                color: theme.bzText2,
                                              ),
                                            ),
                                          )
                                        : BzBnoteMark(
                                            size: 48, color: theme.bzText2),
                                    title: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: value != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: value,
                                              minHeight: 3,
                                              backgroundColor:
                                                  theme.bzSeparator,
                                              color: theme.bzAccent,
                                            ),
                                          )
                                        : Text(
                                            track.id.startsWith('bz:')
                                                ? '${track.artist} · YouTube Music'
                                                : track.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PopupMenuButton<String>(
                                          tooltip: 'Track actions',
                                          icon: BzSvgIcon(
                                            name: 'more-vertical',
                                            color: theme.bzText2,
                                            size: 20,
                                          ),
                                          onSelected: (action) {
                                            if (action == 'playlist') {
                                              _showAddToPlaylist(track);
                                            } else if (action == 'favorite') {
                                              _addFavorite(track);
                                            } else if (action == 'play_next') {
                                              ref.read(playerControllerProvider.notifier).playNext(
                                                TrackInfo(
                                                  id: track.id,
                                                  title: track.title,
                                                  artist: track.artist,
                                                  artworkUrl: track.artworkUrl,
                                                  duration: track.duration,
                                                ),
                                                origin: 'search',
                                                sourceContext: 'Search',
                                              );
                                            } else if (action == 'play_last') {
                                              ref.read(playerControllerProvider.notifier).playLast(
                                                TrackInfo(
                                                  id: track.id,
                                                  title: track.title,
                                                  artist: track.artist,
                                                  artworkUrl: track.artworkUrl,
                                                  duration: track.duration,
                                                ),
                                                origin: 'search',
                                                sourceContext: 'Search',
                                              );
                                            }
                                          },
                                          itemBuilder: (context) => const [
                                            PopupMenuItem(
                                              value: 'play_next',
                                              child: Text('Play Next'),
                                            ),
                                            PopupMenuItem(
                                              value: 'play_last',
                                              child: Text('Add to Queue'),
                                            ),
                                            PopupMenuItem(
                                              value: 'playlist',
                                              child: Text('Add to Playlist'),
                                            ),
                                            PopupMenuItem(
                                              value: 'favorite',
                                              child: Text('Add to Library'),
                                            ),
                                          ],
                                        ),
                                        value != null
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Center(
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                              )
                                            : IconButton(
                                                tooltip: 'Download',
                                                icon: BzSvgIcon(
                                                  name: 'download',
                                                  color: theme.bzText1,
                                                ),
                                                onPressed: () => _download(track),
                                              ),
                                      ],
                                    ),
                                    onTap: () => _play(track),
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text('Recent Searches',
                    style: theme.textTheme.titleLarge),
              ),
              TextButton(
                onPressed: _clearHistory,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final query in _recentSearches)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: BzSvgIcon(name: 'history', color: theme.bzText2),
              title: Text(query,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _reuseSearch(query),
              trailing: IconButton(
                tooltip: 'Remove search',
                icon: BzSvgIcon(name: 'close', color: theme.bzText2),
                onPressed: () => _removeHistory(query),
              ),
            ),
          const SizedBox(height: 20),
        ],
        Text('Suggested searches', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.35,
          children: [
            for (final item in _suggestedSearches.entries)
              Material(
                color: theme.bzSurface1,
                borderRadius: BorderRadius.circular(BzRadius.card),
                child: InkWell(
                  borderRadius: BorderRadius.circular(BzRadius.card),
                  onTap: () => _reuseSearch(item.value),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(BzRadius.card),
                      border: Border.all(color: theme.bzSeparator),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.key,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
