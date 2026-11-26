import '../player/now_playing_screen.dart';
import 'dart:async';
import 'package:file_selector/file_selector.dart';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../video/open_youtube_player.dart';
import '../../core/audio/playback_source_policy.dart';

import '../../app/bootstrap.dart';
import '../../app/downloads_controller.dart';
import '../../app/search_history_store.dart';
import '../../app/playlist_store.dart';
import '../library/add_to_playlists_sheet.dart';
import '../catalog/catalog_detail_screens.dart';
import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../player/player_controller.dart';
import '../player/unified_media_handoff.dart';
import '../../widgets/bz_brand_icons.dart';

/// Search screen — real results from the live source, with local recent
/// searches and live download progress.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final Map<String, SearchHistoryStore> _historyStores = {};
  List<BzTrack> _results = [];
  List<String> _recentSearches = [];
  var _loading = false;
  var _searched = false;
  var _searchLibrary = false;
  var _searchVideos = false;
  var _searchLocal = false;
  // Scope controls become visible only after the first query has resolved.
  var _searchScopesRevealed = false;
  final List<BzTrack> _deviceAudioTracks = [];
  final Map<String, String> _deviceAudioPaths = {};
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
  Timer? _typeaheadTimer;

  SearchHistoryStore get _history {
    final auth = ref.read(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    return _historyStores.putIfAbsent(
      ownerId,
      () => SearchHistoryStore(ownerId: ownerId),
    );
  }


  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _typeaheadTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final auth = ref.read(authSessionProvider);
      final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
      final history = await _history.load();
      if (!mounted) return;
      final current = ref.read(authSessionProvider);
      final currentOwner = current is AuthSignedIn ? current.userId : 'guest';
      if (ownerId != currentOwner) return;
      setState(() => _recentSearches = history);
    } catch (_) {
      // Search must remain usable when local history storage is unavailable.
    }
  }

  void _onQueryChanged(String query) {
    _typeaheadTimer?.cancel();
    _searchGeneration++;
    final normalized = query.trim();
    setState(() {
      _loading = normalized.length >= 2;
      _searched = normalized.length >= 2;
      _results = [];
      _error = null;
      _searchScopesRevealed = false;
    });
    if (normalized.length < 2) return;
    _typeaheadTimer = Timer(const Duration(milliseconds: 500), () {
      _search(normalized, recordHistory: false);
    });
  }

  Future<void> _search(String query, {bool recordHistory = true}) async {
    _typeaheadTimer?.cancel();
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
    if (recordHistory) {
      try {
        final history = await _history.add(normalized);
        if (mounted && generation == _searchGeneration) {
          setState(() => _recentSearches = history);
        }
      } catch (_) {
        // Continue with the music-source request even if persistence fails.
      }
    }

    if (!mounted || generation != _searchGeneration) return;

    if (_searchLocal) {
      // Local results are exclusively from files the user explicitly chose.
      // Never crawl device storage or issue network requests in Local mode.
      final needle = normalized.toLowerCase();
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _searchScopesRevealed = true;
        _results = _deviceAudioTracks.where((track) =>
          track.title.toLowerCase().contains(needle) ||
          track.artist.toLowerCase().contains(needle),
        ).toList();
      });
      return;
    }

    if (_searchLibrary) {
      try {
        final auth = ref.read(authSessionProvider);
        final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
        final favorites = await ref.read(favoritesStoreProvider).load(ownerId: ownerId);
        if (!mounted || generation != _searchGeneration) return;
        final needle = normalized.toLowerCase();
        final matches = favorites.where((item) =>
            item.title.toLowerCase().contains(needle) ||
            item.artist.toLowerCase().contains(needle));
        setState(() {
          _loading = false;
          _searchScopesRevealed = true;
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
          _searchScopesRevealed = true;
          _results = [];
          _error = 'Your library could not be searched right now.';
        });
      }
      return;
    }

    try {
      final isVideoSearch = _searchVideos && !_searchLibrary;
      if (isVideoSearch) {
        // Prefer the existing Original Music Video discovery classification.
        // If the metadata sidecar/discovery query is unavailable, retry with
        // official YouTube Data API embeddable music-video search. The API
        // key remains strictly on our NestJS server, never in Flutter.
        List<Map> videos = <Map>[];
        try {
          final data = await ref.read(authSessionProvider.notifier).api
              .discoveryMusicVideos(query: normalized.toLowerCase() == 'music videos'
                  ? 'official music video'
                  : normalized);
          final raw = data['items'];
          if (raw is List) videos = raw.whereType<Map>().toList();
        } catch (_) {
          // A metadata provider outage must not hide official video results.
        }
        if (videos.isEmpty) {
          try {
            final official = await ref.read(authSessionProvider.notifier).api
                .searchOfficialYouTubeVideos(normalized, limit: 20);
            final results = official['value'];
            if (official['kind'] == 'ok' && results is List) {
              videos = [
                for (final row in results.whereType<Map>())
                  {
                    'id': row['providerTrackId'],
                    'title': row['title'],
                    'artist': row['artist'],
                    'artworkUrl': row['artworkUrl'],
                  },
              ];
            }
          } catch (_) {
            // The visible player still handles IDs already in the library.
          }
        }
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _loading = false;
          _searchScopesRevealed = true;
          _results = videos.where((item) =>
              RegExp(r'^[A-Za-z0-9_-]{11}$')
                  .hasMatch(item['id'] as String? ?? '')).map((item) {
            final id = item['id'] as String;
            final duration = item['durationSec'];
            return BzTrack(
              id: 'bzv:$id',
              title: item['title'] as String? ?? 'Untitled video',
              artist: item['artist'] as String? ?? 'Unknown artist',
              artworkUrl: item['artworkUrl'] as String?,
              duration: Duration(seconds: duration is num ? duration.toInt() : 0),
            );
          }).toList();
        });
      } else {
        final op = await ref.read(catalogSourceProvider).search(normalized);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _loading = false;
          _searchScopesRevealed = true;
          _results = [if (op is ProviderOk<List<ProviderTrack>>) ...op.value
                  .map((track) => BzTrack(
                        id: track.breezzeTrackId,
                        hasPreview: track.hasPreview,
                        title: track.title,
                        artist: track.artist,
                        artworkUrl: track.artworkUrl,
                        duration: track.duration,
                      ))
                  ];
          if (_results.isEmpty && op is! ProviderOk<List<ProviderTrack>>) {
            _error = 'Music catalog search is temporarily unavailable. '
                'Try again in Breezze.';
          }
        });
      }
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
          _searchScopesRevealed = true;
        _results = [];
        if (_results.isEmpty) _error = 'Could not reach the music source. Check your connection.';
      });
    }
  }

  void _selectResultScope({
    bool video = false,
    bool library = false,
    bool local = false,
  }) {
    if (_searchVideos == video &&
        _searchLibrary == library &&
        _searchLocal == local) return;
    _typeaheadTimer?.cancel();
    _searchGeneration++;
    setState(() {
      _searchVideos = video;
      _searchLibrary = library;
      _searchLocal = local;
      _results = [];
      _error = null;
    });
    if (_controller.text.trim().length >= 2) {
      _search(_controller.text, recordHistory: false);
    }
  }

  Future<void> _chooseLocalAudio() async {
    const audio = XTypeGroup(
      label: 'Audio files',
      extensions: ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg'],
      mimeTypes: ['audio/*'],
      uniformTypeIdentifiers: ['public.audio'],
    );
    try {
      // Permission is explicit: only user-selected files become searchable.
      final files = await openFiles(acceptedTypeGroups: [audio]);
      if (!mounted || files.isEmpty) return;
      final batch = DateTime.now().microsecondsSinceEpoch;
      final imported = <BzTrack>[];
      final paths = <String, String>{};
      for (final (index, file) in files.indexed) {
        if (file.path.trim().isEmpty) continue;
        final id = 'device-search:$batch:$index';
        imported.add(BzTrack(
          id: id,
          title: file.name,
          artist: 'On this device',
          duration: Duration.zero,
        ));
        paths[id] = file.path;
      }
      final needle = _controller.text.trim().toLowerCase();
      setState(() {
        _deviceAudioTracks.addAll(imported);
        _deviceAudioPaths.addAll(paths);
        if (_searchLocal) {
          _results = _deviceAudioTracks.where((track) =>
            track.title.toLowerCase().contains(needle) ||
            track.artist.toLowerCase().contains(needle),
          ).toList();
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to open device audio. Try selecting files again.'),
      ));
    }
  }

  Future<void> _removeHistory(String query) async {
    final owner = ref.read(authSessionProvider);
    final ownerId = owner is AuthSignedIn ? owner.userId : 'guest';
    try {
      final history = await _history.remove(query);
      if (!mounted) return;
      final active = ref.read(authSessionProvider);
      if ((active is AuthSignedIn ? active.userId : 'guest') != ownerId) return;
      setState(() => _recentSearches = history);
    } catch (_) {
      // Search stays usable if personal history cannot be written.
    }
  }

  Future<void> _clearHistory() async {
    final owner = ref.read(authSessionProvider);
    final ownerId = owner is AuthSignedIn ? owner.userId : 'guest';
    try {
      await _history.clear();
      if (!mounted) return;
      final active = ref.read(authSessionProvider);
      if ((active is AuthSignedIn ? active.userId : 'guest') != ownerId) return;
      setState(() => _recentSearches = []);
    } catch (_) {
      // Search stays usable if personal history cannot be written.
    }
  }

  void _reuseSearch(String query) {
    if (query.trim().toLowerCase() == 'music videos') {
      setState(() {
        _searchVideos = true;
        _searchLibrary = false;
        _searchLocal = false;
      });
    }
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
    final initialAuth = ref.read(authSessionProvider);
    final ownerId =
        initialAuth is AuthSignedIn ? initialAuth.userId : 'guest';
    bool stillOwner() {
      if (!mounted) return false;
      final current = ref.read(authSessionProvider);
      return initialAuth is AuthSignedIn
          ? current is AuthSignedIn && current.userId == ownerId
          : initialAuth is AuthSignedOut && current is AuthSignedOut;
    }

    final store = PlaylistStore();
    final int? count;
    try {
      count = await addSongToMultiplePlaylists(
      context: context,
      store: store,
      ownerId: ownerId,
      track: FavoriteTrack(
        id: track.id,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.artworkUrl,
        durationMs: track.duration.inMilliseconds,
      ),
      ownerStillActive: stillOwner,
      requestPlaylistName: _requestPlaylistName,
      );
    } catch (_) {
      if (stillOwner()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update playlists. Try again.'),
        ));
      }
      return;
    }
    if (count == null || count == 0 || !stillOwner()) return;
    if (initialAuth is AuthSignedIn) {
      unawaited(store.syncOwner(
        ownerId,
        ref.read(authSessionProvider.notifier).api,
        ownerStillActive: stillOwner,
      ));
    }
    ref.read(playlistRefreshSignalProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count == 1
          ? 'Added to 1 playlist'
          : 'Added to $count playlists'),
    ));
  }

  Future<void> _addFavorite(BzTrack track) async {
    final initialAuth = ref.read(authSessionProvider);
    final ownerId =
        initialAuth is AuthSignedIn ? initialAuth.userId : 'guest';
    bool stillOwner() {
      if (!mounted) return false;
      final current = ref.read(authSessionProvider);
      return initialAuth is AuthSignedIn
          ? current is AuthSignedIn && current.userId == ownerId
          : current is AuthSignedOut || current is AuthUninitialized;
    }

    try {
      final favorites = ref.read(favoritesStoreProvider);
      final alreadySaved =
          await favorites.isFavorite(track.id, ownerId: ownerId);
      // An async lookup may finish after sign-out/account switching. Never
      // write a private favorite for a session that is no longer active.
      if (!stillOwner()) return;
      if (!alreadySaved) {
        await favorites.toggle(
          FavoriteTrack(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkUrl: track.artworkUrl,
            durationMs: track.duration.inMilliseconds,
          ),
          ownerId: ownerId,
        );
      }
      if (!stillOwner()) return;
      ref.invalidate(isTrackFavoriteProvider(
        (ownerId: ownerId, trackId: track.id),
      ));
      ref.read(favoritesRefreshProvider.notifier).state++;
      // The local favorite and outbox are already durable. Network failures
      // must not hide a successful offline save or lose its retry intent.
      try {
        await ref.read(outboxSyncProvider).drainIfSignedIn();
      } catch (_) {
        // The outbox will replay the operation when the user reconnects.
      }
      if (!stillOwner()) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(alreadySaved
            ? 'Already in Library'
            : 'Saved to Library on this device'),
      ));
    } catch (_) {
      if (stillOwner()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save song to Library.')),
        );
      }
    }
  }

  void _download(BzTrack track) {
    // Metadata providers do not grant offline-download rights.
    if (track.id.startsWith('bz:') || track.id.startsWith('bzv:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline downloads are not available for this catalogue source.')),
      );
      return;
    }
    ref.read(downloadProgressProvider.notifier).download(track);
  }

  void _openTrack(BzTrack track) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackDetailScreen(
        track: TrackInfo(
          id: track.id,
          title: track.title,
          artist: track.artist,
          artworkUrl: track.artworkUrl,
          duration: track.duration,
        ),
        relatedTracks: [
          for (final item in _results)
            TrackInfo(
              id: item.id,
              title: item.title,
              artist: item.artist,
              artworkUrl: item.artworkUrl,
              duration: item.duration,
            ),
        ],
        origin: _searchLibrary ? 'library' : 'search',
      ),
    ));
  }

  Future<void> _watchMusicVideo(BzTrack track) async {
    final generation = _searchGeneration;
    try {
      final id = track.id.substring('bz:youtube_music:'.length);
      final result = await ref.read(authSessionProvider.notifier).api.musicVideoForSong(id);
      if (!mounted || generation != _searchGeneration) return;
      final video = result['videoId'];
      if (video is String) {
        await openYouTubePlayer(context: context, ref: ref, videoId: video,
            title: track.title, artist: track.artist, artworkUrl: track.artworkUrl);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No official music video for this recording.')),
        );
      }
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load the music video. Try again.')),
      );
    }
  }

  Future<void> _playDeezerPreview(BzTrack track) async {
    final id = (isDeezerTrackId(track.id) || isDeezerPreview(track.id))
        ? track.id.split(':').last : null;
    if (id == null || (!track.hasPreview && !isDeezerPreview(track.id))) {
      return;
    }
    final previewId = 'bz:deezer_preview:$id';
    final sample = TrackInfo(
      id: previewId,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      duration: const Duration(seconds: 30),
    );
    try {
      await ref.read(playerControllerProvider.notifier).playTrack(
        trackId: previewId,
        queue: [sample],
        startIndex: 0,
        origin: 'deezer-sample',
        sourceContext: 'Deezer preview (30 seconds)',
      );
      if (!mounted) return;
      final state = ref.read(playerControllerProvider);
      if (state.playbackState == PlaybackState.playing) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const NowPlayingScreen(),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Deezer preview unavailable inside Breezze.',
          )),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deezer preview could not start.')),
      );
    }
  }

  Future<void> _play(BzTrack track) async {
    final embeddedId = track.id.startsWith('bzv:')
        ? track.id.substring(4)
        : null;
    if (embeddedId != null) {
      // A video is watched in the official visible iframe, never extracted
      // into Breezze's native audio-only playback queue.
      await openYouTubePlayer(
        context: context,
        ref: ref,
        videoId: embeddedId,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.artworkUrl,
      );
      return;
    }
    // Breezze must never open external streaming apps. These providers'
    // public catalog APIs do not grant full-length, decodable audio bytes.
    // Once a licensed in-app stream is registered, the source-aware backend
    // resolver can use it; until then, report unavailable instead of lying.
    if (isSpotifyTrackId(track.id) || isDeezerTrackId(track.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Full-song playback is not yet licensed for Breezze. '
            'This track cannot currently play in the Breezze player.',
          )),
        );
      }
      return;
    }
    if (isDeezerPreview(track.id)) {
      await _playDeezerPreview(track);
      return;
    }
    if (isYouTubeSongId(track.id)) {
      await playYoutubeMusicWithVideoFallback(
        context: context,
        ref: ref,
        selected: TrackInfo(
          id: track.id, title: track.title, artist: track.artist,
          artworkUrl: track.artworkUrl, duration: track.duration,
        ),
        candidates: [
          for (final item in _results.where((item) => isYouTubeSongId(item.id)))
            TrackInfo(
              id: item.id, title: item.title, artist: item.artist,
              artworkUrl: item.artworkUrl, duration: item.duration,
            ),
        ],
        origin: 'search',
        sourceContext: 'YouTube videos',
        openNowPlaying: true,
      );
      return;
    }
    if (isMetadataOnlyTrackId(track.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This recording requires Spotify or Deezer playback.')),
        );
      }
      return;
    }

    final playableTracks = _results
        .where((item) => !isMetadataOnlyTrackId(item.id) &&
            (!item.id.startsWith('device-search:') ||
                _deviceAudioPaths.containsKey(item.id)))
        .toList();
    final queue = [
      for (final item in playableTracks)
        TrackInfo(
          id: item.id,
          title: item.title,
          artist: item.artist,
          artworkUrl: item.artworkUrl,
          duration: item.duration,
          localFilePath: _deviceAudioPaths[item.id],
        )
    ];
    final index = playableTracks.indexOf(track);
    if (queue.isEmpty || index < 0) return;
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.id,
          queue: queue,
          startIndex: index.clamp(0, queue.length - 1),
          origin: 'search',
          sourceContext: 'Search',
        );
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NowPlayingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      final previousOwner = previous is AuthSignedIn ? previous.userId : 'guest';
      final nextOwner = next is AuthSignedIn ? next.userId : 'guest';
      if (previousOwner != nextOwner) {
        _typeaheadTimer?.cancel();
        _searchGeneration++;
        // A new listener must never inherit the previous account's query.
        // Results/history are already owner-scoped; clear the visible field too.
        _controller.clear();
        setState(() {
          _recentSearches = [];
          _results = [];
          _loading = false;
          _searched = false;
          _error = null;
        });
        _loadHistory();
      }
    });
    final theme = Theme.of(context);
    final progress = ref.watch(downloadProgressProvider);

    // This screen also opens as a standalone route from Browse, where no
    // surrounding Scaffold may provide the required Material ancestor.
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Search', style: theme.textTheme.displayMedium),
                const SizedBox(height: 16),
                // PRT-01 search pill: --radius-pill (capsule) with the
                // surface-hover fill and a leading magnifier — the Apple
                // Music search field treatment.
                TextField(
                  controller: _controller,
                  onSubmitted: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _searchVideos && !_searchLibrary
                        ? 'Search official music videos'
                        : 'Songs, artists and more',
                    prefixIcon: BzSvgIcon(name: 'search', color: theme.bzText2),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: BzSvgIcon(name: 'close', color: theme.bzText2),
                            onPressed: () {
                              _controller.clear();
                              _onQueryChanged('');
                            },
                          ),
                    filled: true,
                    fillColor: theme.bzSurface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BzRadius.capsule),
                      borderSide: BorderSide(color: theme.bzSeparator),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BzRadius.capsule),
                      borderSide: BorderSide(color: theme.bzSeparator),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BzRadius.capsule),
                      borderSide: BorderSide(color: theme.bzAccent),
                    ),
                  ),
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: 10),
                // BitChord-inspired behavior: source choices appear only
                // after a search resolves, never on the empty search landing.
                if (_searchScopesRevealed &&
                    _controller.text.trim().length >= 2) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        BzFilterPill(
                          label: 'Audio',
                          active: !_searchVideos && !_searchLibrary && !_searchLocal,
                          onTap: () => _selectResultScope(),
                        ),
                        const SizedBox(width: 8),
                        BzFilterPill(
                          label: 'Video',
                          active: _searchVideos,
                          onTap: () => _selectResultScope(video: true),
                        ),
                        const SizedBox(width: 8),
                        BzFilterPill(
                          label: 'Library',
                          active: _searchLibrary,
                          onTap: () => _selectResultScope(library: true),
                        ),
                        const SizedBox(width: 8),
                        BzFilterPill(
                          label: 'Local',
                          active: _searchLocal,
                          onTap: () => _selectResultScope(local: true),
                        ),
                      ],
                    ),
                  ),
                  if (_searchLocal) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _chooseLocalAudio,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Choose audio files'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 7,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, __) => const BzSkeletonTrackRow(),
                  )
                : !_searched
                    ? _buildRecentSearches(theme)
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton(
                                    onPressed: _controller.text.trim().isEmpty
                                        ? null
                                        : () => _search(
                                              _controller.text,
                                              recordHistory: false,
                                            ),
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Text(
                                  (_searchLocal
                                      ? 'No matching local songs. Choose audio files above to search your device.'
                                      : _searchVideos && !_searchLibrary
                                          ? 'No official videos found for "${_controller.text.trim()}"'
                                          : 'No results for "${_controller.text.trim()}"'),
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
                                  final musicSearch = !_searchVideos && !_searchLibrary;
                                  final shelf = isSpotifyTrackId(track.id)
                                      ? 'Spotify'
                                      : isDeezerTrackId(track.id)
                                          ? 'Deezer'
                                          : isMusicBrainzTrackId(track.id)
                                              ? 'MusicBrainz · Backup catalog'
                                              : null;
                                  final previous = index == 0 ? null : _results[index - 1];
                                  final previousShelf = previous == null
                                      ? null
                                      : isSpotifyTrackId(previous.id)
                                          ? 'Spotify'
                                          : isDeezerTrackId(previous.id)
                                              ? 'Deezer'
                                              : isMusicBrainzTrackId(previous.id)
                                                  ? 'MusicBrainz · Backup catalog'
                                                  : null;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (musicSearch && shelf != null &&
                                          shelf != previousShelf)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                          child: Text(shelf,
                                              style: theme.textTheme.titleMedium),
                                        ),
                                      ListTile(
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
                                            isSpotifyTrackId(track.id)
                                                ? '${track.artist} · Spotify'
                                                : track.id.startsWith('bz:deezer:') || isDeezerPreview(track.id)
                                                    ? '${track.artist} · Deezer${track.hasPreview ? ' · Preview available' : ''}'
                                                    : isMusicBrainzTrackId(track.id)
                                                        ? '${track.artist} · MusicBrainz metadata'
                                                        : isYouTubeSongId(track.id)
                                                            ? '${track.artist} · YouTube video'
                                                            : track.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    // On compact phones one action menu
                                    // replaces three cramped trailing icons.
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (canOfferPlaybackAction(
                                              track.id, hasPreview: track.hasPreview))
                                          IconButton(
                                            tooltip: track.id.startsWith('bzv:')
                                                ? 'Watch music video'
                                                : isYouTubeSongId(track.id)
                                                    ? 'Watch on YouTube'
                                                    : isDeezerPreview(track.id)
                                                        ? 'Play 30-second sample'
                                                        : 'Play',
                                            icon: const BzSvgIcon(name: 'play', size: 20),
                                            onPressed: () => _play(track),
                                          ),
                                        if (!track.id.startsWith('bzv:'))
                                          PopupMenuButton<String>(
                                            tooltip: 'Song actions',
                                            icon: const BzSvgIcon(name: 'more-vertical', size: 20),
                                            onSelected: (action) {
                                              if (action == 'deezer_preview') {
                                                _playDeezerPreview(track);
                                              } else if (action == 'original') {
                                                openYouTubePlayer(
                                                  context: context,
                                                  ref: ref,
                                                  videoId: track.id.substring('bz:youtube_music:'.length),
                                                  title: track.title,
                                                  artist: track.artist,
                                                  artworkUrl: track.artworkUrl,
                                                );
                                              } else if (action == 'video') {
                                                _watchMusicVideo(track);
                                              } else if (action == 'playlist') {
                                                _showAddToPlaylist(track);
                                              } else if (action == 'favorite') {
                                                _addFavorite(track);
                                              } else if (action == 'download') {
                                                _download(track);
                                              } else if (action == 'play_next' ||
                                                  action == 'play_last') {
                                                final item = TrackInfo(
                                                  id: track.id,
                                                  title: track.title,
                                                  artist: track.artist,
                                                  artworkUrl: track.artworkUrl,
                                                  duration: track.duration,
                                                );
                                                final controller = ref.read(playerControllerProvider.notifier);
                                                if (action == 'play_next') {
                                                  controller.playNext(item,
                                                      origin: 'search',
                                                      sourceContext: 'Search');
                                                } else {
                                                  controller.playLast(item,
                                                      origin: 'search',
                                                      sourceContext: 'Search');
                                                }
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (isSpotifyTrackId(track.id) ||
                                                  isDeezerTrackId(track.id) ||
                                                  isDeezerPreview(track.id)) ...[
                                                const PopupMenuItem(
                                                  value: 'playlist',
                                                  child: Text('Add to Playlists'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'favorite',
                                                  child: Text('Add to Library'),
                                                ),
                                                if ((isDeezerTrackId(track.id) &&
                                                     track.hasPreview) ||
                                                    isDeezerPreview(track.id))
                                                  const PopupMenuItem(
                                                    value: 'deezer_preview',
                                                    child: Text('Play 30-second sample'),
                                                  ),
                                              ]
                                              else ...[
                                                if (isYouTubeSongId(track.id)) ...[
                                                  const PopupMenuItem(value: 'original', child: Text('Open YouTube player')),
                                                  const PopupMenuItem(value: 'video', child: Text('Watch music video')),
                                                ],
                                                const PopupMenuItem(
                                                  value: 'playlist',
                                                  child: Text('Add to Playlists'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'favorite',
                                                  child: Text('Add to Library'),
                                                ),
                                              ],
                                              if (canQueueTrackId(track.id)) ...[
                                                const PopupMenuItem(
                                                  value: 'play_next',
                                                  child: Text('Play Next'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'play_last',
                                                  child: Text('Add to Queue'),
                                                ),
                                              ],
                                              if (canRequestOfflineDownload(track.id))
                                                const PopupMenuItem(
                                                  value: 'download',
                                                  child: Text('Download'),
                                                ),
                                            ],
                                          ),
                                        if (value != null)
                                          const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                      ],
                                    ),
                                    onTap: () => track.id.startsWith('bzv:') ||
                                            isYouTubeSongId(track.id) ||
                                            canQueueTrackId(track.id)
                                        ? _play(track)
                                        : _openTrack(track),
                                      ),
                                    ],
                                  );
                                },
                              ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildRecentSearches(ThemeData theme) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, BzBreakpoints.bottomClearance(context, compact: 180)),
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
