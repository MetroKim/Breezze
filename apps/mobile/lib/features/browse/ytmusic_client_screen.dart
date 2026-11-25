import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../video/open_youtube_player.dart';

/// YouTube Music public discovery and separately consented read-only playlists.
/// Metadata and account access do not grant full-song playback or downloads.
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

bool _ytArtistId(Object? raw) =>
    raw is String && RegExp(r'^[A-Za-z0-9_-]{10,64}$').hasMatch(raw);

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
  return Material(
    color: Colors.transparent,
    child: ListTile(
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
    ),
  );
}

class _YouTubeMusicClientScreenState
    extends ConsumerState<YouTubeMusicClientScreen> {
  Map<String, dynamic>? _explore;
  Map<String, dynamic>? _moods;
  bool _loading = true;
  int _generation = 0;
  int _accountGeneration = 0;
  bool _accountLoading = true;
  bool _accountBusy = false;
  String? _accountError;
  Map<String, dynamic>? _account;
  String? _accountOwnerId;
  List<Map<String, dynamic>> _accountPlaylists = [];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
        _loadConnection();
      }
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

  /// The YouTube account connection is independent of Breezze's login.
  /// Server responses contain public channel/playlist data, never credentials.
  Future<void> _loadConnection() async {
    final generation = ++_accountGeneration;
    final current = ref.read(authSessionProvider);
    if (current is! AuthSignedIn) {
      if (mounted) setState(() {
        _account = null;
        _accountOwnerId = null;
        _accountLoading = false;
        _accountPlaylists = [];
      });
      return;
    }
    if (mounted) setState(() {
      _accountOwnerId = current.userId;
      _account = null;
      _accountPlaylists = [];
      _accountLoading = true;
      _accountError = null;
    });
    final api = ref.read(authSessionProvider.notifier).api;
    try {
      final status = await api.youtubeAccountStatus();
      List<Map<String, dynamic>> playlists = [];
      String? warning;
      if (status['connected'] == true && status['available'] == true) {
        try {
          final response = await api.youtubeAccountPlaylists();
          if (response['source'] == 'youtube_data_api') {
            playlists = _ytRows(response['items']);
          } else {
            warning = 'YouTube playlists are unavailable right now.';
          }
        } catch (_) {
          warning = 'Could not refresh YouTube playlists. Try again.';
        }
      }
      if (!mounted || generation != _accountGeneration) return;
      final latest = ref.read(authSessionProvider);
      if (latest is! AuthSignedIn || latest.userId != current.userId) return;
      setState(() {
        _account = status;
        _accountPlaylists = playlists;
        _accountError = warning;
        _accountLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _accountGeneration) return;
      final latest = ref.read(authSessionProvider);
      if (latest is! AuthSignedIn || latest.userId != current.userId) return;
      setState(() {
        _accountLoading = false;
        _accountError = 'YouTube account connection is not available.';
      });
    }
  }

  Future<void> _connectAccount() async {
    final current = ref.read(authSessionProvider);
    if (current is! AuthSignedIn || _accountBusy) return;
    setState(() => _accountBusy = true);
    try {
      final flow = await ref.read(authSessionProvider.notifier).api
          .youtubeAccountStart();
      final raw = flow['authorizationUrl'];
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null || uri.scheme != 'https' ||
          uri.host != 'accounts.google.com' ||
          uri.path != '/o/oauth2/v2/auth' ||
          uri.queryParameters['scope'] !=
              'https://www.googleapis.com/auth/youtube.readonly') {
        throw StateError('UNSAFE_GOOGLE_CONSENT_URL');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('COULD_NOT_OPEN_CONSENT');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Approve access in Google, then return here and tap Refresh connection.',
        )),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start YouTube account linking.')),
      );
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _disconnectAccount() async {
    final current = ref.read(authSessionProvider);
    if (current is! AuthSignedIn || _accountBusy) return;
    final approve = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect YouTube account?'),
        content: const Text(
          'Breezze will remove its stored YouTube authorization. '
          'Your YouTube account and playlists will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (approve != true || !mounted) return;
    setState(() => _accountBusy = true);
    try {
      await ref.read(authSessionProvider.notifier).api.youtubeAccountDisconnect();
      if (!mounted) return;
      setState(() {
        _account = {'available': true, 'connected': false};
        _accountPlaylists = [];
        _accountError = null;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not disconnect YouTube account.')),
      );
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  void _openYoutubePlaylist(Map<String, dynamic> item) {
    final id = item['playlistId'];
    if (!_ytPlaylistId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtConnectedPlaylistScreen(
        playlistId: id as String,
        title: item['title'] as String? ?? 'Your YouTube playlist',
      ),
    ));
  }

  Widget _accountSection(ThemeData theme) {
    final auth = ref.watch(authSessionProvider);
    if (auth is! AuthSignedIn) return const SizedBox.shrink();
    // Never display a previous Breezze listener's linked YouTube account
    // while an authentication/account switch is in progress.
    final sameOwner = _accountOwnerId == auth.userId;
    final account = sameOwner ? _account : null;
    final playlists = sameOwner ? _accountPlaylists : const <Map<String, dynamic>>[];
    final connected = account?['connected'] == true;
    final available = account?['available'] == true;
    return Container(
      decoration: BoxDecoration(
        color: theme.bzSurface1,
        borderRadius: BorderRadius.circular(BzRadius.card),
        border: Border.all(color: theme.bzSeparator),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your YouTube account', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Separate Google consent • read-only YouTube playlists. '
            'Not a full YouTube Music library or music download permission.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.bzText2),
          ),
          if (_accountLoading && sameOwner) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ] else ...[
            const SizedBox(height: 12),
            if (connected)
              Text(
                'Connected: ' + (account?['channelTitle'] as String? ??
                  'YouTube channel'),
              )
            else
              Text(available
                ? 'Your YouTube account is not connected.'
                : 'Account connection is not configured yet.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!connected)
                  OutlinedButton(
                    onPressed: available && !_accountBusy
                        ? _connectAccount : null,
                    child: const Text('Connect YouTube'),
                  ),
                OutlinedButton(
                  onPressed: !_accountBusy ? _loadConnection : null,
                  child: const Text('Refresh connection'),
                ),
                if (connected)
                  TextButton(
                    onPressed: _accountBusy ? null : _disconnectAccount,
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
            if (sameOwner && _accountError != null) ...[
              const SizedBox(height: 8),
              Text(_accountError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.bzText2)),
            ],
            if (connected) ...[
              const SizedBox(height: 16),
              Text('Your YouTube playlists',
                style: theme.textTheme.titleMedium),
              if (playlists.isEmpty)
                const Material(
                  color: Colors.transparent,
                  child: ListTile(
                    title: Text('No playlists available'),
                    subtitle: Text(
                      'This view shows playlists returned by the official '
                      'YouTube Data API, not all YouTube Music library items.',
                    ),
                  ),
                ),
              for (final playlist in playlists)
                _ytRow(playlist,
                  subtitle: 'Your YouTube playlist • read-only',
                  onTap: _ytPlaylistId(playlist['playlistId'])
                      ? () => _openYoutubePlaylist(playlist) : null,
                ),
            ],
          ],
        ],
      ),
    );
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
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      final oldOwner = previous is AuthSignedIn ? previous.userId : null;
      final newOwner = next is AuthSignedIn ? next.userId : null;
      if (oldOwner == newOwner) return;
      // Account-specific YouTube data cannot survive a Breezze account switch.
      _accountGeneration++;
      setState(() {
        _account = null;
        _accountOwnerId = null;
        _accountPlaylists = [];
        _accountError = null;
        _accountLoading = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadConnection();
      });
    });
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
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const _YtSongSearchScreen(),
                                    ),
                                  ),
                                  child: const Text('Find songs'),
                                ),
                                OutlinedButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const _YtArtistSearchScreen(),
                                    ),
                                  ),
                                  child: const Text('Find artists'),
                                ),
                                OutlinedButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const _YtChartsScreen(),
                                    ),
                                  ),
                                  child: const Text('Music charts'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _accountSection(theme),
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


/// Authorized playlists are obtained through the YouTube Data API; do not
/// treat them as a complete YouTube Music library or as download grants.
class _YtConnectedPlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String title;

  const _YtConnectedPlaylistScreen({
    required this.playlistId,
    required this.title,
  });

  @override
  ConsumerState<_YtConnectedPlaylistScreen> createState() =>
      _YtConnectedPlaylistScreenState();
}

class _YtConnectedPlaylistScreenState
    extends ConsumerState<_YtConnectedPlaylistScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final current = ref.read(authSessionProvider);
    if (current is! AuthSignedIn) return;
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final response = await ref.read(authSessionProvider.notifier).api
          .youtubeAccountPlaylistItems(widget.playlistId);
      if (response['source'] != 'youtube_data_api' ||
          response['playlistId'] != widget.playlistId) {
        throw const FormatException('UNTRUSTED_YOUTUBE_PLAYLIST');
      }
      final items = _ytRows(response['items']);
      if (!mounted) return;
      final latest = ref.read(authSessionProvider);
      if (latest is! AuthSignedIn || latest.userId != current.userId) return;
      setState(() {
        _items = items;
        _hasMore = response['hasMore'] == true;
      });
    } catch (_) {
      if (mounted) setState(
        () => _error = 'Your YouTube playlist is unavailable. Retry.',
      );
    }
  }

  Future<void> _watch(Map<String, dynamic> item) async {
    final videoId = item['videoId'];
    if (!_ytVideoId(videoId)) return;
    await openYouTubePlayer(
      context: context,
      ref: ref,
      videoId: videoId as String,
      title: item['title'] as String? ?? 'YouTube video',
      artist: _ytArtist(item),
      artworkUrl: item['artworkUrl'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: _error != null
        ? Center(child: OutlinedButton(
            onPressed: _load,
            child: Text(_error!),
          ))
        : _items == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  const ListTile(
                    title: Text('Your YouTube playlist'),
                    subtitle: Text(
                      'Read-only • videos use the official YouTube player. '
                      'Offline YouTube downloads are not available.',
                    ),
                  ),
                  if (_items!.isEmpty)
                    const ListTile(title: Text('No videos in this playlist')),
                  for (final item in _items!)
                    _ytRow(item,
                      subtitle: _ytArtist(item),
                      actionLabel: 'Open official YouTube player',
                      onTap: _ytVideoId(item['videoId'])
                          ? () => _watch(item) : null,
                    ),
                  if (_hasMore)
                    const ListTile(
                      title: Text('More playlist items available'),
                      subtitle: Text(
                        'Showing the first 50 items. Pagination is not yet available.',
                      ),
                    ),
                ],
              ),
  );
}


/// Artist search remains public metadata and never requests a media URL.
class _YtArtistSearchScreen extends ConsumerStatefulWidget {
  const _YtArtistSearchScreen();
  @override
  ConsumerState<_YtArtistSearchScreen> createState() => _YtArtistSearchState();
}

class _YtArtistSearchState extends ConsumerState<_YtArtistSearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>>? _artists;
  String? _error;
  bool _busy = false;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    final generation = ++_generation;
    if (query.length < 2 || query.length > 120) {
      setState(() => _error = 'Enter an artist name (2–120 characters).');
      return;
    }
    setState(() { _busy = true; _error = null; _artists = null; });
    try {
      final data = _ytValue(await ref.read(authSessionProvider.notifier).api
          .ytMusicSearchArtists(query));
      if (!mounted || generation != _generation) return;
      setState(() { _artists = _ytRows(data['artists']); _busy = false; });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = 'Artist search unavailable • Retry';
      });
    }
  }

  void _open(Map<String, dynamic> item) {
    final id = item['artistId'];
    if (!_ytArtistId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtArtistScreen(
        artistId: id as String,
        title: item['name'] as String? ?? 'Artist',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('YouTube Music artists')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Public artist discovery • songs open in the visible '
            'YouTube player, not native audio or downloads.'),
        TextField(
          controller: _query,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: 'Artist name'),
          onSubmitted: (_) { _search(); },
        ),
        OutlinedButton(
          onPressed: _busy ? null : _search,
          child: const Text('Search artists'),
        ),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!),
        if (_artists != null) ...[
          Text('Artists', style: Theme.of(context).textTheme.titleLarge),
          if (_artists!.isEmpty)
            const ListTile(title: Text('No matching artists found')),
          for (final item in _artists!)
            _ytRow(
              {...item, 'title': item['name']},
              subtitle: 'YouTube Music public artist',
              onTap: _ytArtistId(item['artistId']) ? () => _open(item) : null,
            ),
        ],
      ],
    ),
  );
}

/// Artist songs use the existing visible YouTube handoff; albums are metadata.
class _YtArtistScreen extends ConsumerStatefulWidget {
  const _YtArtistScreen({required this.artistId, required this.title});
  final String artistId;
  final String title;
  @override
  ConsumerState<_YtArtistScreen> createState() => _YtArtistState();
}

class _YtArtistState extends ConsumerState<_YtArtistScreen> {
  Map<String, dynamic>? _artist;
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
    final data = await _ytOptional(() => ref.read(authSessionProvider.notifier)
        .api.ytMusicArtist(widget.artistId));
    if (!mounted) return;
    final raw = data?['artist'];
    final item = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : null;
    setState(() {
      _artist = item != null &&
          item['artistId'] == widget.artistId &&
          item['name'] is String ? item : null;
      _loading = false;
    });
  }

  Future<void> _watch(Map<String, dynamic> item) async {
    final id = item['providerTrackId'];
    if (!_ytVideoId(id)) return;
    await openYouTubePlayer(
      context: context, ref: ref, videoId: id as String,
      title: item['title'] as String? ?? 'YouTube Music',
      artist: _artist?['name'] as String? ?? widget.title,
      artworkUrl: item['artworkUrl'] as String?,
    );
  }

  void _openAlbum(Map<String, dynamic> item) {
    final id = item['browseId'];
    if (!_ytAlbumId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtCollectionScreen(
        id: id as String, album: true,
        title: item['title'] as String? ?? 'Album',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final item = _artist;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : item == null
          ? Center(child: OutlinedButton(
              onPressed: _load,
              child: const Text('Artist unavailable • Retry'),
            ))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(item['name'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (item['description'] is String)
                  Text(item['description'] as String),
                const Text('Metadata only • songs use the visible '
                    'YouTube player; offline downloads are unavailable.'),
                Text('Top songs',
                    style: Theme.of(context).textTheme.titleLarge),
                for (final song in _ytRows(item['topSongs']))
                  _ytRow(song,
                    subtitle: item['name'] as String,
                    actionLabel: 'Open visible YouTube player',
                    onTap: _ytVideoId(song['providerTrackId'])
                        ? () => _watch(song) : null),
                Text('Albums',
                    style: Theme.of(context).textTheme.titleLarge),
                for (final album in _ytRows(item['albums']))
                  _ytRow(album,
                    subtitle: 'Public album',
                    onTap: _ytAlbumId(album['browseId'])
                        ? () => _openAlbum(album) : null),
              ],
            ),
    );
  }
}

class _YtChartsScreen extends ConsumerStatefulWidget {
  const _YtChartsScreen();
  @override
  ConsumerState<_YtChartsScreen> createState() => _YtChartsState();
}

class _YtChartsState extends ConsumerState<_YtChartsScreen> {
  Map<String, dynamic>? _charts;
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
    final data = await _ytOptional(() =>
        ref.read(authSessionProvider.notifier).api.ytMusicCharts());
    if (!mounted) return;
    setState(() {
      _charts = data?['country'] == 'ZZ' ? data : null;
      _loading = false;
    });
  }

  void _openArtist(Map<String, dynamic> item) {
    final id = item['artistId'];
    if (!_ytArtistId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtArtistScreen(
        artistId: id as String, title: item['name'] as String? ?? 'Artist'),
    ));
  }

  void _openPlaylist(Map<String, dynamic> item) {
    final id = item['playlistId'];
    if (!_ytPlaylistId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtCollectionScreen(
        id: id as String, album: false,
        title: item['title'] as String? ?? 'Playlist'),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('YouTube Music charts')),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _charts == null
        ? Center(child: OutlinedButton(
            onPressed: _load,
            child: const Text('Charts unavailable • Retry'),
          ))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Public global charts • regional data may vary.'),
              if (_charts!['songRankingAvailable'] != true)
                const ListTile(
                  title: Text('Verified Top Songs rankings unavailable'),
                ),
              Text('Featured artists',
                  style: Theme.of(context).textTheme.titleLarge),
              for (final artist in _ytRows(_charts!['artists']))
                _ytRow({...artist, 'title': artist['name']},
                  subtitle: 'Public chart artist',
                  onTap: _ytArtistId(artist['artistId'])
                      ? () => _openArtist(artist) : null),
              Text('Music-video playlists',
                  style: Theme.of(context).textTheme.titleLarge),
              for (final playlist in _ytRows(_charts!['musicVideoPlaylists']))
                _ytRow(playlist,
                  subtitle: 'Public video playlist',
                  onTap: _ytPlaylistId(playlist['playlistId'])
                      ? () => _openPlaylist(playlist) : null),
            ],
          ),
  );
}

class _YtSongSearchScreen extends ConsumerStatefulWidget {
  const _YtSongSearchScreen();

  @override
  ConsumerState<_YtSongSearchScreen> createState() => _YtSongSearchState();
}

class _YtSongSearchState extends ConsumerState<_YtSongSearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>>? _songs;
  String? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    final generation = ++_generation;
    if (query.length < 2 || query.length > 120) {
      setState(() {
        _songs = null;
        _error = 'Enter a song or artist name (2–120 characters).';
      });
      return;
    }
    setState(() { _loading = true; _songs = null; _error = null; });
    try {
      final result = await ref.read(authSessionProvider.notifier).api
          .ytMusicSearchSongs(query);
      if (result['kind'] != 'ok' || result['value'] is! List) {
        throw const FormatException('YTMUSIC_SEARCH_UNAVAILABLE');
      }
      if (!mounted || generation != _generation) return;
      setState(() { _songs = _ytRows(result['value']); _loading = false; });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Song search unavailable • Retry';
      });
    }
  }

  Future<void> _watch(Map<String, dynamic> song) async {
    final id = song['providerTrackId'];
    if (!_ytVideoId(id)) return;
    await openYouTubePlayer(
      context: context,
      ref: ref,
      videoId: id as String,
      title: song['title'] as String? ?? 'YouTube Music',
      artist: _ytArtist(song),
      artworkUrl: song['artworkUrl'] as String?,
    );
  }

  void _related(Map<String, dynamic> song) {
    final id = song['providerTrackId'];
    if (!_ytVideoId(id)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _YtWatchQueueScreen(
        videoId: id as String,
        title: song['title'] as String? ?? 'Song',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube Music song search')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              children: [
                Text('Find songs', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Search the public catalog. Songs open in the visible '
                  'official YouTube player; metadata does not grant '
                  'native audio or downloads.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                const SizedBox(height: 20),
                TextField(
                  controller: _query,
                  maxLength: 120,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Song or artist',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) { _search(); },
                ),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('Search songs'),
                ),
                if (_loading) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!),
                ],
                if (_songs != null) ...[
                  const SizedBox(height: 20),
                  Text('Songs', style: theme.textTheme.titleLarge),
                  if (_songs!.isEmpty)
                    const ListTile(title: Text('No matching songs found')),
                  for (final song in _songs!)
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: _ytArtwork(song['artworkUrl'] as String?),
                        title: Text(song['title'] as String? ?? 'Untitled'),
                        subtitle: Text(_ytArtist(song) + ' • Watch on YouTube'),
                        onTap: _ytVideoId(song['providerTrackId'])
                            ? () => _watch(song) : null,
                        trailing: IconButton(
                          tooltip: 'Up next for ' + (song['title'] as String? ?? 'Song'),
                          icon: const Icon(Icons.queue_music),
                          onPressed: _ytVideoId(song['providerTrackId'])
                              ? () => _related(song) : null,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YtWatchQueueScreen extends ConsumerStatefulWidget {
  const _YtWatchQueueScreen({required this.videoId, required this.title});
  final String videoId;
  final String title;

  @override
  ConsumerState<_YtWatchQueueScreen> createState() => _YtWatchQueueState();
}

class _YtWatchQueueState extends ConsumerState<_YtWatchQueueScreen> {
  Map<String, dynamic>? _queue;
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
    final data = await _ytOptional(() =>
        ref.read(authSessionProvider.notifier).api
            .ytMusicWatchQueue(widget.videoId));
    if (!mounted) return;
    setState(() {
      _queue = data != null &&
              data['seedVideoId'] == widget.videoId &&
              data['playbackAvailable'] == false ? data : null;
      _loading = false;
    });
  }

  Future<void> _watch(Map<String, dynamic> song) async {
    final id = song['providerTrackId'];
    if (!_ytVideoId(id)) return;
    await openYouTubePlayer(
      context: context,
      ref: ref,
      videoId: id as String,
      title: song['title'] as String? ?? 'YouTube Music',
      artist: _ytArtist(song),
      artworkUrl: song['artworkUrl'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _queue == null
            ? Center(child: OutlinedButton(
                onPressed: _load,
                child: const Text('Related songs unavailable • Retry'),
              ))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Up next',
                      style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('Public YouTube Music suggestions. Choose a song '
                      'to watch in the official player. This is not a native '
                      'playback queue or a download playlist.'),
                    const SizedBox(height: 16),
                    if (_ytRows(_queue!['tracks']).isEmpty)
                      const ListTile(title: Text('No related songs available')),
                    for (final song in _ytRows(_queue!['tracks']))
                      _ytRow(
                        song,
                        subtitle: _ytArtist(song),
                        actionLabel: 'Watch in official YouTube player',
                        onTap: _ytVideoId(song['providerTrackId'])
                            ? () => _watch(song) : null,
                      ),
                  ],
                ),
              ),
  );
}
