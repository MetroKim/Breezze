import 'dart:async';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/main_tab.dart';

import '../../app/breezze_navigation.dart';
import '../../app/bootstrap.dart';
import '../../app/recent_store.dart';
import '../../app/playlist_store.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../core/audio/playback_source_policy.dart';
import '../video/open_youtube_player.dart';
import '../player/player_controller.dart';
import '../settings/settings_screen.dart';
import '../settings/account_screen.dart';
import '../search/search_screen.dart';
import '../../widgets/bz_discovery_spotlight.dart';
import '../../widgets/bz_morphing_brand_header.dart';
import '../../widgets/bz_pinned_mood_rail.dart';
import '../../widgets/bz_discovery_action_tile.dart';

/// Listen Now home — real rails from persisted history (§03).
///
/// Recently Played comes from the RecentStore; Favorites from the
/// FavoritesStore. No placeholder data presented as real (§50.1).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.loadRecent});

  /// An account-scoped history reader. Defaults to the persistent RecentStore.
  /// This seam also makes account-switch and storage-failure behavior testable.
  final Future<List<RecentEntry>> Function(String ownerId)? loadRecent;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<RecentEntry> _recentlyPlayed = [];
  List<FavoriteTrack> _favorites = [];
  List<TrackInfo> _madeForYou = [];
  List<TrackInfo> _deezerTrending = [];
  Map<String, dynamic>? _replay;
  bool _loading = true;
  bool _localDataUnavailable = false;
  int _refreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final version = ++_refreshVersion;
    final auth = ref.read(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    // A broken local store must not leave Listen Now on skeletons forever.
    // Continue to fetch any independent remote sections without claiming
    // that missing local rows are real history or recommendations.
    var localDataUnavailable = false;
    List<RecentEntry> recent;
    try {
      final load = widget.loadRecent;
      recent = load != null
          ? await load(ownerId)
          : await RecentStore().load(ownerId: ownerId);
    } catch (_) {
      recent = [];
      localDataUnavailable = true;
    }
    if (!mounted || version != _refreshVersion) return;
    List<FavoriteTrack> favorites;
    try {
      favorites = await ref.read(favoritesStoreProvider).load(ownerId: ownerId);
    } catch (_) {
      favorites = [];
      localDataUnavailable = true;
    }
    Map<String, dynamic>? replay;
    var madeForYou = <TrackInfo>[];
    var deezerTrending = <TrackInfo>[];
    if (!mounted || version != _refreshVersion) return;
    if (auth is AuthSignedIn) {
      final api = ref.read(authSessionProvider.notifier).api;
      try {
        final sections = await api.homeFeed();
        Map<String, dynamic>? personalized;
        for (final section in sections) {
          if (section['sectionType'] == 'personalized') {
            personalized = section;
            break;
          }
        }
        final rawIds = personalized?['trackIds'];
        final ids = rawIds is List
            ? rawIds.whereType<String>().where((id) => id.isNotEmpty).take(12)
            : const <String>[];
        final resolved = await Future.wait(ids.map((id) async {
          try {
            final song = await api.catalogSong(id);
            final artistData = song['artist'];
            final duration = song['duration'];
            return TrackInfo(
              id: song['id'] as String? ?? id,
              title: song['title'] as String? ?? '',
              artist: artistData is Map
                  ? artistData['name'] as String? ?? ''
                  : '',
              artworkUrl: song['artworkUrl'] as String?,
              duration: Duration(
                seconds: duration is num ? duration.toInt() : 0,
              ),
            );
          } catch (_) {
            // A track can become unavailable between ranking and display.
            return null;
          }
        }));
        madeForYou = resolved.whereType<TrackInfo>()
            .where((track) => track.title?.isNotEmpty == true)
            .toList(growable: false);
      } catch (_) {
        // Personalized content is optional; local listening history remains.
      }
      try {
        replay = await api.replaySummary();
      } catch (_) {
        // Replay is an independent home section.
      }
      try {
        final chart = await api.discoverySongsChart();
        final rows = chart['items'];
        if (rows is List && chart['source'] == 'Deezer') {
          // Do not queue raw full-track Deezer metadata identifiers.
          deezerTrending = rows.whereType<Map>().where((row) {
            final id = row['id']?.toString() ?? '';
            return RegExp(r'^[0-9]{1,20}$').hasMatch(id) &&
                row['previewUrl'] is String &&
                (row['title'] as String?)?.isNotEmpty == true &&
                (row['artist'] as String?)?.isNotEmpty == true;
          }).take(12).map((row) => TrackInfo(
            id: 'bz:deezer_preview:${row['id']}',
            title: row['title'] as String,
            artist: row['artist'] as String,
            artworkUrl: row['artworkUrl'] as String?,
            duration: const Duration(seconds: 30),
          )).toList(growable: false);
        }
      } catch (_) {
        // A Deezer outage must not hide saved Home content.
      }
    }
    if (!mounted || version != _refreshVersion) return;
    final currentAuth = ref.read(authSessionProvider);
    final currentOwnerId =
        currentAuth is AuthSignedIn ? currentAuth.userId : 'guest';
    if (currentOwnerId != ownerId) return;
    setState(() {
      _recentlyPlayed = recent;
      _favorites = favorites;
      _madeForYou = madeForYou;
      _deezerTrending = deezerTrending;
      _replay = replay;
      _loading = false;
      _localDataUnavailable = localDataUnavailable;
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
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    final store = PlaylistStore();
    await store.create(ownerId, name);
    if (auth is AuthSignedIn) {
      unawaited(store.syncOwner(
        ownerId,
        ref.read(authSessionProvider.notifier).api,
        ownerStillActive: () {
          if (!mounted) return false;
          final current = ref.read(authSessionProvider);
          return current is AuthSignedIn && current.userId == ownerId;
        },
      ));
    }
    if (!mounted) return;
    ref.read(homeTabHintProvider.notifier).state = MainTab.library.index;
    ref.read(playlistRefreshSignalProvider.notifier).state++;
  }

  Future<void> _play(TrackInfo track, List<TrackInfo> queue, int index) async {
    if (isMetadataOnlyTrackId(track.id) && !isYouTubeSongId(track.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This catalog entry has no authorized in-app playback source.')),
        );
      }
      return;
    }
    if (isYouTubeSongId(track.id)) {
      await openYouTubePlayer(
        context: context,
        ref: ref,
        videoId: track.id.substring('bz:youtube_music:'.length),
        title: track.title ?? 'YouTube Music',
        artist: track.artist ?? 'Unknown artist',
        artworkUrl: track.artworkUrl,
      );
      return;
    }
    await ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.id,
          queue: queue,
          startIndex: index,
          origin: 'home',
          sourceContext: 'Listen Now',
        );
  }

  /// Time-based greeting from the local clock; no network dependency.
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good late night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      final before = previous is AuthSignedIn ? previous.userId : null;
      final after = next is AuthSignedIn ? next.userId : null;
      if (before == after) return;
      setState(() {
        _recentlyPlayed = [];
        _favorites = [];
        _madeForYou = [];
        _deezerTrending = [];
        _replay = null;
        _loading = true;
        _localDataUnavailable = false;
      });
      _refresh();
    });
    final theme = Theme.of(context);
    final shortcuts = <String, TrackInfo>{};
    for (final r in _recentlyPlayed) {
      if (shortcuts.length >= 6) break;
      shortcuts[r.id] = TrackInfo(id: r.id, title: r.title, artist: r.artist, artworkUrl: r.artworkUrl, duration: r.duration);
    }

    // A barely visible neutral ambient tint above an otherwise #000 OLED
    // canvas. No colored branding wash or whole-page backdrop blur.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.19, 0.40],
          colors: [Color(0xFF0D0D10), Color(0xFF050506), Colors.black],
        ),
      ),
      child: SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            BzMorphingBrandHeader(
              sidebarBrandOnDesktop: true,
              actions: [
                IconButton(
                  tooltip: 'Create playlist',
                  onPressed: _createPlaylist,
                  icon: BzSvgIcon(name: 'plus', color: theme.bzAccent),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: BzSvgIcon(name: 'more-vertical', color: theme.bzText1),
                  onSelected: (value) {
                    if (value == 'settings') {
                      Navigator.of(context).push(
                        breezzePageRoute<void>(
                          context: context,
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                  ],
                ),
                IconButton(
                  tooltip: 'Account and profile',
                  onPressed: () => Navigator.of(context).push(
                    breezzePageRoute<void>(
                      context: context,
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                  icon: BzSvgIcon(name: 'user-round', color: theme.bzText1),
                ),
              ],
            ),
            // The original reference pins discovery filters underneath its
            // masthead. Breezze keeps that interaction but uses our own mood
            // taxonomy and authenticated music-search route.
            BzPinnedMoodRail(
              moods: const ['Energy', 'Focus', 'Relax', 'Workout', 'Chill', 'Commute'],
              onMoodSelected: (mood) => Navigator.of(context).push(
                breezzePageRoute<void>(
                  context: context,
                  builder: (_) => SearchScreen(initialQuery: '$mood music'),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  16, 14, 16, BzBreakpoints.bottomClearance(context, compact: 220)),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          // The Flutter discovery pattern is inspired by editorial music
          // browsers, not copied from the unlicensed reference source.
          Text(_greeting, style: theme.textTheme.displayMedium),
          const SizedBox(height: 20),
          if (_loading) ...[
            const BzSkeleton(width: 172, height: 16, radius: 5),
            const SizedBox(height: 16),
            for (var i = 0; i < 3; i++) ...[
              const BzSkeletonTrackRow(),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 18),
            const BzSkeletonArtworkGrid(itemCount: 4),
          ],
          if (!_loading && _localDataUnavailable) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.bzSurface1,
                borderRadius: BorderRadius.circular(BzRadius.card),
                border: Border.all(color: theme.bzSeparator),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Could not load your saved music',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Your listening history or saved songs are temporarily unavailable. Your library has not been erased.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (!_loading && shortcuts.isNotEmpty) ...[
            _ShortcutGrid(tracks: shortcuts.values.toList(), onPlay: _play),
            const SizedBox(height: 28),
          ],
          if (!_loading && _madeForYou.isNotEmpty) ...[
            _Rail(
              title: 'Made for You',
              tracks: _madeForYou,
              onPlay: _play,
            ),
            const SizedBox(height: 24),
          ],
          if (!_loading && _deezerTrending.isNotEmpty) ...[
             _Rail(
               title: 'Trending on Deezer · 30-second previews',
               tracks: _deezerTrending,
               onPlay: _play,
             ),
             const SizedBox(height: 24),
           ],
           if (!_loading && _recentlyPlayed.isNotEmpty) ...[
            _Rail(
              title: 'Recently Played',
              tracks: [
                for (final r in _recentlyPlayed)
                  TrackInfo(
                    id: r.id,
                    title: r.title,
                    artist: r.artist,
                    artworkUrl: r.artworkUrl,
                    duration: r.duration,
                  )
              ],
              onPlay: _play,
            ),
            const SizedBox(height: 24),
          ],
          // Render the genuine music sessions before promotional chrome,
          // following the reference's music-first Home hierarchy.
          const SizedBox(height: 16),
          BzDiscoverySpotlight(
            eyebrow: 'Breezze discovery',
            title: 'Your next favorite starts here',
            description: 'Explore music, artists and videos from real catalog results.',
            actionLabel: 'Explore New',
            onAction: () => ref.read(homeTabHintProvider.notifier).state =
                MainTab.browse.index,
          ),
          const SizedBox(height: 24),
          Text('Discover in Breezze', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 740
                  ? 3
                  : constraints.maxWidth >= 330
                      ? 2
                      : 1;
              final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: BzDiscoveryActionTile(
                      label: 'New releases',
                      description: 'Music and albums',
                      iconName: 'disc-3',
                      onTap: () => ref.read(homeTabHintProvider.notifier).state =
                          MainTab.browse.index,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: BzDiscoveryActionTile(
                      label: 'Music videos',
                      description: 'Official video search',
                      iconName: 'video',
                      onTap: () => Navigator.of(context).push(
                        breezzePageRoute<void>(
                          context: context,
                          builder: (_) => const SearchScreen(
                            initialQuery: 'official music video',
                            initialVideoSearch: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: BzDiscoveryActionTile(
                      label: 'Find artists',
                      description: 'Search artist profiles',
                      iconName: 'user-round',
                      onTap: () => ref.read(homeTabHintProvider.notifier).state =
                          MainTab.search.index,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (!_loading && (_recentlyPlayed.isNotEmpty || _favorites.isNotEmpty)) ...[
            _Rail(
              title: 'Your Mix',
              tracks: [
                ..._recentlyPlayed.map((r) => TrackInfo(id: r.id, title: r.title, artist: r.artist, artworkUrl: r.artworkUrl, duration: r.duration)),
                ..._favorites.map((f) => f.toTrackInfo()).where((f) => !_recentlyPlayed.any((r) => r.id == f.id)),
              ],
              onPlay: _play,
            ),
            const SizedBox(height: 24),
          ],
          if (!_loading && _favorites.isNotEmpty) ...[
            _Rail(
              title: 'Your Favorites',
              tracks: [
                for (final f in _favorites)
                  f.toTrackInfo()
              ],
              onPlay: _play,
            ),
            const SizedBox(height: 24),
          ],
          // A compact vertical list follows the horizontal shelves. Every
          // title, artist and thumbnail comes from this owner's real history.
          if (!_loading && _recentlyPlayed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Continue listening',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var i = 0; i < _recentlyPlayed.length && i < 8; i++)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(BzRadius.artwork),
                  child: _recentlyPlayed[i].artworkUrl == null
                      ? SizedBox(
                          width: 52, height: 52,
                          child: Center(
                            child: BzBnoteMark(
                              size: 26, color: theme.bzText2,
                            ),
                          ),
                        )
                      : Image.network(
                          _recentlyPlayed[i].artworkUrl!,
                          width: 52, height: 52, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              BzBnoteMark(size: 52, color: theme.bzText2),
                        ),
                ),
                title: Text(
                  _recentlyPlayed[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _recentlyPlayed[i].artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: BzSvgIcon(
                  name: 'play', size: 18, color: theme.bzText2,
                ),
                onTap: () {
                  final queue = [
                    for (final item in _recentlyPlayed)
                      TrackInfo(
                        id: item.id,
                        title: item.title,
                        artist: item.artist,
                        artworkUrl: item.artworkUrl,
                        duration: item.duration,
                      ),
                  ];
                  _play(queue[i], queue, i);
                },
              ),
            const SizedBox(height: 22),
          ],
          if (!_loading && !_localDataUnavailable && _recentlyPlayed.isEmpty && _favorites.isEmpty)
            _FirstRunCard(
              onSearch: () => ref.read(homeTabHintProvider.notifier).state = MainTab.search.index,
            ),
          if (_replay != null && ((_replay!['totalPlays'] as num?)?.toInt() ?? 0) > 0)
            _ReplayCard(summary: _replay!),
                ]),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Hint provider: tapping the first-run card can nudge the shell to the
/// Search tab (the shell reads this provider's value when building).
final homeTabHintProvider = StateProvider<int>((ref) => 0);

/// Shortcut tile grid (§4.1 section 2): up to 6 recently played items as
/// compact chips — artwork, title, artist on surface1 cards. Real
/// history only; nothing fabricated.
class _ShortcutGrid extends StatelessWidget {
  final List<TrackInfo> tracks;
  final void Function(TrackInfo, List<TrackInfo>, int) onPlay;

  const _ShortcutGrid({required this.tracks, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2 columns compact, 3 medium, 4+ wide (Apple Music grid density).
        final width = constraints.maxWidth;
        final columns = width >= 1080 ? 4 : width >= 620 ? 3 : 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < tracks.length; i++)
              _ShortcutTile(
                track: tracks[i],
                width: (width - 10 * (columns - 1)) / columns,
                onTap: () => onPlay(tracks[i], tracks, i),
              ),
          ],
        );
      },
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final TrackInfo track;
  final double width;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.track,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Play ${track.title ?? 'track'}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: 64,
          decoration: BoxDecoration(
            color: theme.bzSurface1,
            borderRadius: BorderRadius.circular(BzRadius.button),
            border: Border.all(color: theme.bzSeparator),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(BzRadius.button),
                ),
                child: track.artworkUrl != null
                    ? Image.network(
                        track.artworkUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          color: theme.bzSurface2,
                          alignment: Alignment.center,
                          child: BzBnoteMark(size: 26, color: theme.bzText2),
                        ),
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: theme.bzSurface2,
                        alignment: Alignment.center,
                        child: BzBnoteMark(size: 26, color: theme.bzText2),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: BzType.footnote,
                        fontWeight: FontWeight.w600,
                        color: theme.bzText1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: BzType.caption,
                        color: theme.bzText2,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: BzSvgIcon(name: 'play', size: 16, color: theme.bzText2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal content rail with real tracks (§3.2).
class _Rail extends StatelessWidget {
  final String title;
  final List<TrackInfo> tracks;
  final void Function(TrackInfo, List<TrackInfo>, int) onPlay;

  const _Rail({required this.title, required this.tracks, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title,
              style: TextStyle(
                  fontSize: BzType.title3,
                  fontWeight: FontWeight.w600,
                  color: theme.bzText1)),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final track = tracks[i];
              return _TrackCard(
                track: track,
                onTap: () => onPlay(track, tracks, i),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Track card — artwork, title, artist (§3.2 card anatomy).
/// Press feedback: scale 0.96 spring (§5.2). Reduced motion collapses
/// to the resting state instantly.
class _TrackCard extends StatefulWidget {
  final TrackInfo track;
  final VoidCallback onTap;

  const _TrackCard({required this.track, required this.onTap});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.track;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: BzMotion.fastMs),
        curve: Curves.easeOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: theme.bzSurface2,
                borderRadius: BorderRadius.circular(BzRadius.artwork),
                border: Border.all(color: theme.bzSeparator),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BzRadius.artwork),
                child: track.artworkUrl != null
                    ? Image.network(
                        track.artworkUrl!,
                        width: 150,
                        height: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child:
                              BzBnoteMark(size: 48, color: theme.bzText2),
                        ),
                      )
                    : Center(
                        child:
                            BzBnoteMark(size: 48, color: theme.bzText2),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(track.title ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: BzType.headline,
                    fontWeight: FontWeight.w600,
                    color: theme.bzText1)),
            Text(track.artist ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: BzType.footnote, color: theme.bzText2)),
          ],
        ),
      ),
    );
  }
}

/// First-run card — the honest empty state pointing to Search.
class _FirstRunCard extends StatelessWidget {
  final VoidCallback onSearch;

  const _FirstRunCard({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.bzSurface1,
        borderRadius: BorderRadius.circular(BzRadius.card),
        border: Border.all(color: theme.bzSeparator),
      ),
      child: Column(
        children: [
          BzBnoteMark(size: 56, color: theme.bzText2),
          const SizedBox(height: 16),
          Text('Find your first song', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('The music you play appears in Recently Played.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onSearch,
            icon: BzSvgIcon(name: 'search', size: 18, color: theme.colorScheme.onPrimary),
            label: const Text('Search music'),
          ),
        ],
      ),
    );
  }
}


class _ReplayCard extends StatelessWidget {
  const _ReplayCard({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songs = summary['topSongIds'] is List
        ? (summary['topSongIds'] as List).whereType<Map>().toList()
        : const <Map>[];
    final artists = summary['topArtistIds'] is List
        ? (summary['topArtistIds'] as List).whereType<Map>().toList()
        : const <Map>[];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.bzSurface1,
        borderRadius: BorderRadius.circular(BzRadius.card),
        border: Border.all(color: theme.bzSeparator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR REPLAY', style: theme.textTheme.labelSmall?.copyWith(
            color: theme.bzText2, letterSpacing: 1, fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: 8),
          Text('${summary['totalPlays'] ?? 0} plays',
              style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          if (songs.isNotEmpty) ...[
            Text('TOP SONGS', style: theme.textTheme.labelSmall),
            for (final song in songs.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(song['title'] as String? ?? 'Track'),
                subtitle: Text(song['artist'] as String? ?? ''),
                trailing: Text('${song['plays'] ?? 0}'),
              ),
          ],
          if (artists.isNotEmpty) ...[
            Text('TOP ARTISTS', style: theme.textTheme.labelSmall),
            for (final artist in artists.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(artist['name'] as String? ?? 'Artist'),
                trailing: Text('${artist['plays'] ?? 0}'),
              ),
          ],
        ],
      ),
    );
  }
}
