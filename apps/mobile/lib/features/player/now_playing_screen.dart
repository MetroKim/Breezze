import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../widgets/bz_brand_icons.dart';
import '../player/player_controller.dart';

/// Now Playing — premium edition: ambient artwork backdrop (content is
/// the colour), breathing artwork on the calm 2s loop, word-synced
/// karaoke lyrics.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  Lyrics? _lyrics;
  String _lyricsMode = 'none';
  int _lyricsRequestGeneration = 0;
  bool _lyricsVisible = true;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final request = ++_lyricsRequestGeneration;
    final track = ref.read(playerControllerProvider).currentTrack;
    if (track == null || track.title == null) {
      if (mounted) {
        setState(() {
          _lyrics = null;
          _lyricsMode = 'none';
        });
      }
      return;
    }

    setState(() {
      _lyrics = null;
      _lyricsMode = 'loading';
    });

    try {
      final result = await ref.read(lyricsProvider).bestFor(BzTrack(
            id: track.id,
            title: track.title!,
            artist: track.artist ?? '',
            duration: track.duration,
          ));
      if (!mounted || request != _lyricsRequestGeneration) return;
      if (result == null) {
        setState(() => _lyricsMode = 'none');
        return;
      }
      final synced = result.syncedLrc != null;
      setState(() {
        _lyrics = LrcParser.parse(track.id, result.bestLrc);
        _lyricsMode = synced ? 'synced' : 'plain';
      });
    } catch (_) {
      if (!mounted || request != _lyricsRequestGeneration) return;
      setState(() {
        _lyrics = null;
        _lyricsMode = 'none';
      });
    }
  }

  void _openPlayingNext() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).bzBackground,
      builder: (_) => const _PlayingNextSheet(),
    );
  }


  void _showPlayerActions(
    BuildContext context,
    PlayerController controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).bzBackground,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const BzSvgIcon(name: 'queue'),
              title: const Text('Playing Next'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPlayingNext();
              },
            ),
            ListTile(
              leading: const BzSvgIcon(name: 'shuffle'),
              title: const Text('Shuffle queue'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.toggleShuffle();
              },
            ),
            ListTile(
              leading: const BzSvgIcon(name: 'repeat'),
              title: const Text('Change repeat mode'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.cycleRepeat();
              },
            ),
            ListTile(
              leading: BzSvgIcon(name: _lyricsVisible ? 'lyrics' : 'lyrics'),
              title: Text(_lyricsVisible ? 'Hide lyrics' : 'Show lyrics'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _lyricsVisible = !_lyricsVisible);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = (d - Duration(minutes: m)).inSeconds;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      playerControllerProvider.select((state) => state.currentTrack?.id),
      (previous, next) {
        if (previous != next) _loadLyrics();
      },
    );
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final theme = Theme.of(context);
    final track = player.currentTrack;
    final playing = player.playbackState == PlaybackState.playing;

    if (track == null) {
      return Scaffold(
        backgroundColor: theme.bzBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BzBnoteMark(size: 72, color: theme.bzText2),
              const SizedBox(height: 16),
              Text('Nothing playing', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: BzAmbientBackdrop(
        artworkUrl: track.artworkUrl,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: BzSvgIcon(name: 'chevron-down'),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('PLAYING FROM',
                              style: TextStyle(
                                  fontSize: BzType.caption,
                                  letterSpacing: 1,
                                  color: theme.bzText2)),
                          Text('Breezze',
                              style: TextStyle(
                                  fontSize: BzType.footnote,
                                  color: theme.bzText1)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: BzSvgIcon(name: 'more-vertical'),
                      onPressed: () => _showPlayerActions(context, controller),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _BreathingArtwork(
                playing: playing,
                artworkUrl: track.artworkUrl,
                fallbackColor: theme.bzText2,
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title ?? 'Unknown track',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(track.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: BzType.body,
                                  color: theme.bzText2)),
                        ],
                      ),
                    ),
                    _FavoriteButton(track: track),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: player.duration > Duration.zero
                            ? player.position.inMilliseconds
                                .clamp(0, player.duration.inMilliseconds)
                                .toDouble()
                            : 0,
                        max: player.duration.inMilliseconds > 0
                            ? player.duration.inMilliseconds.toDouble()
                            : 1,
                        onChanged: (v) => controller
                            .seekTo(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_format(player.position),
                            style: TextStyle(
                                fontSize: BzType.caption,
                                color: theme.bzText2)),
                        Text(_format(player.duration),
                            style: TextStyle(
                                fontSize: BzType.caption,
                                color: theme.bzText2)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              BzGlassContainer(
                radius: BzRadius.capsule,
                blur: 18,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: BzSvgIcon(name: 'shuffle'),
                        onPressed: controller.toggleShuffle,
                        color: theme.bzText2,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Previous track',
                        icon: BzSvgIcon(name: 'skip-previous', size: 34),
                        onPressed: controller.previous,
                      ),
                      const SizedBox(width: 8),
                      _PlayPauseButton(
                        playing: playing,
                        size: 64,
                        onTap: controller.togglePlayPause,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Next track',
                        icon: BzSvgIcon(name: 'skip-next', size: 34),
                        onPressed: controller.next,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Repeat',
                        icon: BzSvgIcon(name: 'repeat'),
                        onPressed: controller.cycleRepeat,
                        color: theme.bzText2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _lyricsVisible = !_lyricsVisible),
                    icon: BzSvgIcon(name: 'lyrics', size: 18),
                    label: Text(_lyricsVisible ? 'Hide Lyrics' : 'Show Lyrics'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _openPlayingNext,
                    icon: BzSvgIcon(name: 'queue', size: 18),
                    label: const Text('Playing Next'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _lyricsVisible
                    ? _LyricsView(
                        lyrics: _lyrics,
                        mode: _lyricsMode,
                        position: player.position,
                      )
                    : Center(
                        child: Text(
                          'Lyrics hidden',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.bzText2),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreathingArtwork extends StatefulWidget {
  final bool playing;
  final String? artworkUrl;
  final Color fallbackColor;

  const _BreathingArtwork({
    required this.playing,
    required this.artworkUrl,
    required this.fallbackColor,
  });

  @override
  State<_BreathingArtwork> createState() => _BreathingArtworkState();
}

class _BreathingArtworkState extends State<_BreathingArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
    lowerBound: 0.96,
    upperBound: 1.0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BreathingArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      if (widget.playing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    return ScaleTransition(
      scale: _controller,
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(BzRadius.artwork),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BzRadius.artwork),
          child: widget.artworkUrl != null
              ? Image.network(
                  widget.artworkUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: BzBnoteMark(size: 96, color: widget.fallbackColor),
                  ),
                )
              : Center(
                  child: BzBnoteMark(size: 96, color: widget.fallbackColor),
                ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final double size;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.playing,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.bzText1,
          shape: BoxShape.circle,
        ),
        child: BzSvgIcon(
          name: playing ? 'pause' : 'play',
          color: theme.bzBackground,
          size: size * 0.42,
        ),
      ),
    );
  }
}

class _LyricsView extends StatelessWidget {
  final Lyrics? lyrics;
  final String mode;
  final Duration position;

  const _LyricsView({
    required this.lyrics,
    required this.mode,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (mode == 'loading') {
      return const Center(child: CircularProgressIndicator());
    }

    if (mode == 'none' || lyrics == null || lyrics!.lines.isEmpty) {
      return Center(
        child: Text(
          'No lyrics available for this track',
          style: TextStyle(fontSize: BzType.subheadline, color: theme.bzText2),
        ),
      );
    }

    final activeIndex = lyrics!.activeLineIndex(position);
    final isSynced = mode == 'synced';

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: lyrics!.lines.length,
      itemBuilder: (context, i) {
        final line = lyrics!.lines[i];
        final active = i == activeIndex;
        final activeWord =
            active && isSynced ? lyrics!.activeWordIndex(i, position) : -1;

        if (line.words.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: BzType.headline,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? theme.bzText1 : theme.bzText2,
              ),
              child: Text(line.text),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(
            children: [
              for (var w = 0; w < line.words.length; w++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: BzType.headline,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active
                          ? (w <= activeWord ? theme.bzText1 : theme.bzText2)
                          : theme.bzText2,
                    ),
                    child: Text(line.words[w].text),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FavoriteButton extends ConsumerStatefulWidget {
  final TrackInfo track;

  const _FavoriteButton({required this.track});

  @override
  ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  @override
  void didUpdateWidget(covariant _FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final value = await ref.read(favoritesStoreProvider).isFavorite(widget.track.id);
    if (mounted) setState(() => _isFavorite = value);
  }

  Future<void> _toggleFavorite() async {
    final track = widget.track;
    final added = await ref.read(favoritesStoreProvider).toggle(
          FavoriteTrack(
            id: track.id,
            title: track.title ?? '',
            artist: track.artist ?? '',
            artworkUrl: track.artworkUrl,
            durationMs: track.duration.inMilliseconds,
          ),
        );
    if (!mounted) return;
    setState(() => _isFavorite = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? 'Added to favorites' : 'Removed from favorites'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: _isFavorite ? 'Remove favorite' : 'Add favorite',
      icon: BzSvgIcon(
        name: _isFavorite ? 'star-filled' : 'star',
        color: _isFavorite ? theme.bzWarning : theme.bzText2,
        size: 23,
      ),
      onPressed: _toggleFavorite,
    );
  }
}


class _PlayingNextSheet extends ConsumerWidget {
  const _PlayingNextSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final queue = controller.queue;
    final upcoming = queue.upNext;
    final theme = Theme.of(context);
    final current = player.currentTrack;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Playing Next',
                        style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: queue.shuffle ? 'Disable shuffle' : 'Shuffle',
                    onPressed: controller.toggleShuffle,
                    icon: BzSvgIcon(
                      name: 'shuffle',
                      color: queue.shuffle ? theme.bzAccent : theme.bzText2,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Change repeat mode',
                    onPressed: controller.cycleRepeat,
                    icon: BzSvgIcon(
                      name: 'repeat',
                      color: queue.repeatMode == RepeatMode.off
                          ? theme.bzText2
                          : theme.bzAccent,
                    ),
                  ),
                  TextButton(
                    onPressed: upcoming.isEmpty
                        ? null
                        : () => queue.clear(keepCurrent: true),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            if (current != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.bzSurface1,
                    borderRadius: BorderRadius.circular(BzRadius.card),
                    border: Border.all(color: theme.bzSeparator),
                  ),
                  child: Row(
                    children: [
                      BzBnoteMark(size: 36, color: theme.bzAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Now Playing',
                                style: TextStyle(
                                  color: theme.bzAccent,
                                  fontSize: BzType.caption,
                                  fontWeight: FontWeight.w700,
                                )),
                            Text(current.title ?? 'Unknown track',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(current.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.bzText2,
                                  fontSize: BzType.footnote,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('UP NEXT',
                  style: TextStyle(
                    color: theme.bzText2,
                    fontSize: BzType.caption,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  )),
            ),
            Expanded(
              child: upcoming.isEmpty
                  ? Center(
                      child: Text(
                        'No upcoming tracks in the queue.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.bzText2),
                      ),
                    )
                  : ListView.builder(
                      itemCount: upcoming.length,
                      itemBuilder: (context, index) {
                        final entry = upcoming[index];
                        final info = controller.trackInfoFor(entry.trackId);
                        return Dismissible(
                          key: ValueKey(entry.entryId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            color: theme.bzError,
                            child: BzSvgIcon(
                              name: 'trash',
                              color: theme.bzBackground,
                            ),
                          ),
                          onDismissed: (_) => queue.remove(entry.entryId),
                          child: ListTile(
                            leading: BzBnoteMark(
                                size: 40, color: theme.bzText2),
                            title: Text(
                              info?.title ?? 'Track',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              info?.artist ?? entry.sourceContext,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove from queue',
                              onPressed: () => queue.remove(entry.entryId),
                              icon: BzSvgIcon(
                                name: 'close',
                                color: theme.bzText2,
                                size: 18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
