import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../app/recent_store.dart';
import '../../app/playlist_store.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../player/player_controller.dart';
import '../settings/settings_screen.dart';

/// Listen Now home — real rails from persisted history (§03).
///
/// Recently Played comes from the RecentStore; Favorites from the
/// FavoritesStore. No placeholder data presented as real (§50.1).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _recent = RecentStore();
  List<RecentEntry> _recentlyPlayed = [];
  List<FavoriteTrack> _favorites = [];
  Map<String, dynamic>? _replay;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final recent = await _recent.load();
    final favorites = await ref.read(favoritesStoreProvider).load();
    Map<String, dynamic>? replay;
    if (ref.read(authSessionProvider) is AuthSignedIn) {
      try {
        replay = await ref.read(authSessionProvider.notifier).api.replaySummary();
      } catch (_) {
        // Local listening history remains available during an API outage.
      }
    }
    if (!mounted) return;
    setState(() {
      _recentlyPlayed = recent;
      _favorites = favorites;
      _replay = replay;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when returning to this tab (IndexedStack keeps state alive).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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
    await PlaylistStore().create(ownerId, name);
    if (!mounted) return;
    ref.read(homeTabHintProvider.notifier).state = 3;
    ref.read(playlistRefreshSignalProvider.notifier).state++;
  }

  void _play(TrackInfo track, List<TrackInfo> queue, int index) {
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.id,
          queue: queue,
          startIndex: index,
          origin: 'home',
          sourceContext: 'Listen Now',
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 220),
        children: [
          Row(
            children: [
              BzRibbonLogo(width: 96, color: theme.bzText1),
              const Spacer(),
              IconButton(
                tooltip: 'Share Breezze',
                onPressed: null,
                icon: BzSvgIcon(name: 'share', color: theme.bzText2),
              ),
              IconButton(
                tooltip: 'Create playlist',
                onPressed: _createPlaylist,
                icon: SvgPicture.asset(
                  'assets/icons/plus.svg',
                  width: 21,
                  height: 21,
                  colorFilter: ColorFilter.mode(
                    theme.bzAccent,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More options',
                icon: BzSvgIcon(name: 'more-vertical', color: theme.bzText1),
                onSelected: (value) {
                  if (value == 'settings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                ],
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.bzSurface1,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.bzSeparator),
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.asset(
                      'assets/icons/profile.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        theme.bzText1,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Listen Now', style: theme.textTheme.displayMedium),
          const SizedBox(height: 8),
          Text('Your music. Every platform. One line.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          if (_recentlyPlayed.isNotEmpty) ...[
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
          if (_recentlyPlayed.isNotEmpty || _favorites.isNotEmpty) ...[
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
          if (_favorites.isNotEmpty) ...[
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
          if (_recentlyPlayed.isEmpty && _favorites.isEmpty)
            _FirstRunCard(
              onSearch: () => ref.read(homeTabHintProvider.notifier).state = 4,
            ),
          const SizedBox(height: 28),
          const _FeedPlaceholder(
            title: 'Shared With You',
            description:
                'Music shared by friends will appear here when Breezze sharing is connected.',
            status: 'SHARED MUSIC',
          ),
          const SizedBox(height: 24),
          const _FeedPlaceholder(
            title: 'Your Mixes',
            description:
                'Personalized mixes will appear here as your listening profile and recommendation service become available.',
            status: 'MADE FOR YOU',
          ),
          const SizedBox(height: 24),
          if (_replay != null && ((_replay!['totalPlays'] as num?)?.toInt() ?? 0) > 0)
            _ReplayCard(summary: _replay!)
          else
            const _FeedPlaceholder(
              title: 'Your Replay',
              description:
                  'Your listening recap will appear here as your Breezze listening history grows.',
              status: 'YOUR YEAR IN MUSIC',
            ),
        ],
      ),
    );
  }
}

/// Hint provider: tapping the first-run card can nudge the shell to the
/// Search tab (the shell reads this provider's value when building).
final homeTabHintProvider = StateProvider<int>((ref) => 0);

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

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: BzMotion.fastMs),
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
          Text('Nothing here yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Search for a song and play it — it will show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}


class _FeedPlaceholder extends StatelessWidget {
  final String title;
  final String description;
  final String status;

  const _FeedPlaceholder({
    required this.title,
    required this.description,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.bzSurface1,
            borderRadius: BorderRadius.circular(BzRadius.card),
            border: Border.all(color: theme.bzSeparator),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status,
                style: TextStyle(
                  color: theme.bzText2,
                  fontSize: BzType.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.bzText2,
                ),
              ),
            ],
          ),
        ),
      ],
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
