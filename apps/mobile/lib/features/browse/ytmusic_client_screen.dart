import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../video/open_youtube_player.dart';

/// Public YouTube Music companion discovery, inside Breezze's existing Browse
/// tab. Account-library endpoints, media extraction and downloads are absent.
class YouTubeMusicClientScreen extends ConsumerStatefulWidget {
  const YouTubeMusicClientScreen({super.key});

  @override
  ConsumerState<YouTubeMusicClientScreen> createState() =>
      _YouTubeMusicClientScreenState();
}

List<Map<String, dynamic>> _ytRows(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((row) =>
      row.map((key, value) => MapEntry(key.toString(), value))).toList();
}

Map<String, dynamic> _ytValue(Map<String, dynamic> response) {
  if (response['kind'] != 'ok' || response['value'] is! Map) {
    throw const FormatException('YOUTUBE_MUSIC_UNAVAILABLE');
  }
  final data = (response['value'] as Map)
      .map((key, value) => MapEntry(key.toString(), value));
  if (data['source'] != 'youtube_music') {
    throw const FormatException('YOUTUBE_MUSIC_SOURCE_MISMATCH');
  }
  return data;
}

Future<Map<String, dynamic>?> _ytOptional(
  Future<Map<String, dynamic>> Function() load,
) async {
  try {
    return _ytValue(await load());
  } catch (_) {
    return null;
  }
}

bool _ytVideoId(Object? raw) =>
    raw is String && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(raw);

bool _ytPlaylistId(Object? raw) =>
    raw is String && RegExp(r'^[A-Za-z0-9_-]{10,128}$').hasMatch(raw);

bool _ytAlbumId(Object? raw) =>
    raw is String && RegExp(r'^MPRE[A-Za-z0-9_-]{6,60}$').hasMatch(raw);

String _ytArtist(Map<String, dynamic> item) {
  final artist = item['artist'];
  if (artist is String && artist.trim().isNotEmpty) return artist;
  final artists = item['artists'];
  if (artists is List) {
    final names = artists.whereType<String>().where((x) => x.isNotEmpty);
    if (names.isNotEmpty) return names.join(', ');
  }
  return 'YouTube Music';
}

Widget _ytArtwork(String? url) {
  final parsed = url == null ? null : Uri.tryParse(url);
  if (parsed == null || parsed.scheme != 'https') {
    return const SizedBox(
      width: 48, height: 48,
      child: Center(child: BzSvgIcon(name: 'music-note', size: 24)),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(
      url!, width: 48, height: 48, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox(
        width: 48, height: 48,
        child: Center(child: BzSvgIcon(name: 'music-note', size: 24)),
      ),
    ),
  );
}

Widget _ytRow(
  Map<String, dynamic> item, {
  required String subtitle,
  required VoidCallback? onTap,
  String? actionLabel,
}) {
  return ListTile(
    leading: _ytArtwork(item['artworkUrl'] as String?),
    title: Text(
      item['title'] as String? ?? 'Untitled',
      maxLines: 1, overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: IconButton(
      tooltip: actionLabel ?? 'View YouTube Music details',
      onPressed: onTap,
      icon: const BzSvgIcon(name: 'chevron-right', size: 20),
    ),
    onTap: onTap,
  );
}

class _YouTubeMusicClientScreenState
    extends ConsumerState<YouTubeMusicClientScreen> {
  Map<String, dynamic>? _explore;
  Map<String, dynamic>? _moods;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    final api = ref.read(authSessionProvider.notifier).api;
    final results = await Future.wait([
      _ytOptional(api.ytMusicExplore),
      _ytOptional(api.ytMusicMoods),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      _explore = results[0];
      _moods = results[1];
      _loading = false;
    });
  }

  Future<void> _watch(Map<String, dynamic> item, String idKey) async {
    final id = item[idKey];
    if (!_ytVideoId(id)) return;
    await openYouTubePlayer(
      context: context,
      ref: ref,
      videoId: id as String,
      title: item['title'] as String? ?? 'YouTube Music',
      artist: _ytArtist(item),
      artworkUrl: item['artworkUrl'] as String?,
    );
  }

  void _openAlbum(Map<String, dynamic> item) {
    final id = item['albumId'];
    if (!_ytAlbumId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtCollectionScreen(
        id: id as String, album: true,
        title: item['title'] as String? ?? 'Album',
      ),
    ));
  }

  void _openMood(Map<String, dynamic> item) {
    final params = item['params'];
    if (params is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{6,256}$').hasMatch(params)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtMoodPlaylistsScreen(
        params: params, title: item['title'] as String? ?? 'Mood',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final explore = _explore;
    final moods = _moods;
    final releases = _ytRows(explore?['newReleases']);
    final trending = _ytRows(explore?['trending']);
    final videos = _ytRows(explore?['newVideos']);
    final sections = _ytRows(moods?['sections']);
    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: AppBar(
        title: const Text('YouTube Music'),
        actions: [
          IconButton(
            tooltip: 'Refresh YouTube Music',
            onPressed: _loading ? null : _load,
            icon: const BzSvgIcon(name: 'refresh', size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : explore == null && moods == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('YouTube Music catalog is unavailable'),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _load,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                          children: [
                            Text('Explore YouTube Music',
                                style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 6),
                            Text(
                              'Public catalog • videos use the official player. '
                              'Your personal YouTube Music library is not connected.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.bzText2),
                            ),
                            if (explore == null)
                              const ListTile(
                                title: Text('Explore is temporarily unavailable'),
                              ),
                            if (releases.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text('New releases',
                                  style: theme.textTheme.titleLarge),
                              for (final item in releases)
                                _ytRow(item,
                                  subtitle: _ytArtist(item),
                                  onTap: _ytAlbumId(item['albumId'])
                                      ? () => _openAlbum(item) : null,
                                ),
                            ],
                            if (trending.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text('Trending songs',
                                  style: theme.textTheme.titleLarge),
                              for (final item in trending)
                                _ytRow(item,
                                  subtitle: _ytArtist(item) + ' • Watch on YouTube',
                                  actionLabel: 'Open visible YouTube player',
                                  onTap: _ytVideoId(item['providerTrackId'])
                                      ? () => _watch(item, 'providerTrackId')
                                      : null,
                                ),
                            ],
                            if (videos.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text('Official music videos',
                                  style: theme.textTheme.titleLarge),
                              for (final item in videos)
                                _ytRow(item,
                                  subtitle: _ytArtist(item),
                                  actionLabel: 'Watch official music video',
                                  onTap: _ytVideoId(item['videoId'])
                                      ? () => _watch(item, 'videoId') : null,
                                ),
                            ],
                            if (sections.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text('Moods & activities',
                                  style: theme.textTheme.titleLarge),
                              for (final section in sections) ...[
                                const SizedBox(height: 8),
                                Text(section['title'] as String? ?? 'Moods',
                                    style: theme.textTheme.titleMedium),
                                for (final category
                                    in _ytRows(section['categories']))
                                  _ytRow(category,
                                    subtitle: 'YouTube Music playlists',
                                    onTap: category['params'] is String
                                        ? () => _openMood(category) : null,
                                  ),
                              ],
                            ],
                            if (releases.isEmpty && trending.isEmpty &&
                                videos.isEmpty && sections.isEmpty)
                              const ListTile(
                                title: Text('No public catalog items available'),
                                subtitle: Text(
                                  'Content varies by YouTube Music region and availability.',
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}

class _YtMoodPlaylistsScreen extends ConsumerStatefulWidget {
  final String title;
  final String params;
  const _YtMoodPlaylistsScreen({required this.title, required this.params});

  @override
  ConsumerState<_YtMoodPlaylistsScreen> createState() =>
      _YtMoodPlaylistsScreenState();
}

class _YtMoodPlaylistsScreenState
    extends ConsumerState<_YtMoodPlaylistsScreen> {
  List<Map<String, dynamic>>? _playlists;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final result = await _ytOptional(() =>
        ref.read(authSessionProvider.notifier).api
            .ytMusicMoodPlaylists(widget.params));
    if (!mounted) return;
    setState(() => _playlists = _ytRows(result?['playlists']));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: _playlists == null
        ? const Center(child: CircularProgressIndicator())
        : _playlists!.isEmpty
            ? Center(child: OutlinedButton(
                onPressed: _load,
                child: const Text('No playlists found • Retry'),
              ))
            : ListView(
                children: [
                  for (final item in _playlists!)
                    _ytRow(item,
                      subtitle: 'Public YouTube Music playlist',
                      onTap: _ytPlaylistId(item['playlistId'])
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _YtCollectionScreen(
                                  id: item['playlistId'] as String,
                                  album: false,
                                  title: item['title'] as String? ?? 'Playlist',
                                ),
                              ),
                            )
                          : null,
                    ),
                ],
              ),
  );
}

class _YtCollectionScreen extends ConsumerStatefulWidget {
  final String id;
  final bool album;
  final String title;
  const _YtCollectionScreen({
    required this.id, required this.album, required this.title,
  });

  @override
  ConsumerState<_YtCollectionScreen> createState() =>
      _YtCollectionScreenState();
}

class _YtCollectionScreenState extends ConsumerState<_YtCollectionScreen> {
  Map<String, dynamic>? _collection;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ref.read(authSessionProvider.notifier).api;
    final result = await _ytOptional(() => widget.album
        ? api.ytMusicAlbum(widget.id)
        : api.ytMusicPlaylist(widget.id));
    if (!mounted) return;
    setState(() {
      final content = result?[widget.album ? 'album' : 'playlist'];
      _collection = content is Map
          ? content.map((key, value) => MapEntry(key.toString(), value))
          : null;
      _loading = false;
    });
  }

  Future<void> _watch(Map<String, dynamic> item) async {
    final id = item['providerTrackId'];
    if (!_ytVideoId(id)) return;
    await openYouTubePlayer(
      context: context,
      ref: ref,
      videoId: id as String,
      title: item['title'] as String? ?? 'YouTube Music',
      artist: _ytArtist(item),
      artworkUrl: item['artworkUrl'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _ytRows(_collection?['tracks']);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _collection == null
              ? Center(child: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Catalog unavailable • Retry'),
                ))
              : ListView(
                  children: [
                    const ListTile(
                      title: Text('YouTube Music public catalog'),
                      subtitle: Text(
                        'Songs open the visible YouTube player; '
                        'offline downloads are not available.',
                      ),
                    ),
                    if (rows.isEmpty)
                      const ListTile(title: Text('No tracks available')),
                    for (final item in rows)
                      _ytRow(item,
                        subtitle: _ytArtist(item),
                        actionLabel: 'Open visible YouTube player',
                        onTap: _ytVideoId(item['providerTrackId'])
                            ? () => _watch(item) : null,
                      ),
                  ],
                ),
    );
  }
}
