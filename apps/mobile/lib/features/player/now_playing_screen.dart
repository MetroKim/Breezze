import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/cupertino.dart' show
    CupertinoActionSheet, CupertinoActionSheetAction,
    CupertinoTheme, CupertinoThemeData, showCupertinoModalPopup;
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_transport_controls.dart';
import '../player/player_controller.dart';

/// Cover artwork, lyrics and queue share a single playback session.
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
  // Artwork-first playback and a dedicated lyric-reading mode share the
  // same player and synced lyric state, without duplicate audio sessions.
  bool _lyricsFocus = false;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final request = ++_lyricsRequestGeneration;
    final track = ref.read(playerControllerProvider).currentTrack;
    if (track == null || track.title == null || track.id.startsWith('device:')) {
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
    // Shared action model; only the presentation varies by platform.
    final actions = <({String label, String icon, VoidCallback execute})>[
      (label: 'Playing Next', icon: 'queue', execute: _openPlayingNext),
      (label: 'Shuffle queue', icon: 'shuffle',
        execute: controller.toggleShuffle),
      (label: 'Change repeat mode', icon: 'repeat',
        execute: controller.cycleRepeat),
      (label: _lyricsVisible ? 'Hide lyrics' : 'Show lyrics',
        icon: 'lyrics',
        execute: () => setState(() {
          _lyricsVisible = !_lyricsVisible;
          if (!_lyricsVisible) _lyricsFocus = false;
        })),
    ];
    void dispatch(BuildContext sheetContext, VoidCallback action) {
      Navigator.of(sheetContext).pop();
      action();
    }

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final theme = Theme.of(context);
      showCupertinoModalPopup<void>(
        context: context,
        semanticsDismissible: true,
        builder: (sheetContext) => CupertinoTheme(
          data: CupertinoThemeData(
            brightness: theme.brightness,
            primaryColor: theme.bzText1,
          ),
          child: CupertinoActionSheet(
            title: const Text('Playback actions'),
            actions: [
              for (final action in actions)
                CupertinoActionSheetAction(
                  onPressed: () => dispatch(sheetContext, action.execute),
                  child: Text(action.label),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ),
      );
      return;
    }

    // Android and desktop retain Breezze's neutral Material sheet.
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).bzBackground,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                leading: BzSvgIcon(name: action.icon),
                title: Text(action.label),
                onTap: () => dispatch(sheetContext, action.execute),
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
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Close',
                  icon: BzSvgIcon(name: 'chevron-down'),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BzBnoteMark(size: 72, color: theme.bzText2),
                      const SizedBox(height: 16),
                      Text('Nothing playing', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Back to music'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: BzAmbientBackdrop(
        artworkUrl: track.artworkUrl,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: LayoutBuilder(builder: (context, bounds) {
                final minHeight = MediaQuery.textScalerOf(context).scale(1) * 540;
                final height = bounds.maxHeight < minHeight ? minHeight : bounds.maxHeight;
                return SingleChildScrollView(
                  child: SizedBox(
                    height: height,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Close',
                                icon: BzSvgIcon(name: 'chevron-down'),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text('PLAYING FROM',
                                        style: TextStyle(
                                            fontSize: BzType.caption,
                                            letterSpacing: 1,
                                            color: theme.bzText2)),
                                    Text(controller.queue.playingFromLabel ?? 'Breezze',
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: BzType.footnote,
                                            color: theme.bzText1)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'More actions',
                                icon: BzSvgIcon(name: 'more-vertical'),
                                onPressed: () =>
                                    _showPlayerActions(context, controller),
                              ),
                            ],
                          ),
                        ),
                        // Portrait artwork mode follows the cover-led design.
                        // Focus mode gives the actual synced lyrics the full
                        // reading surface while retaining playback controls.
                        if (!_lyricsFocus) const Spacer(),
                        if (!_lyricsFocus)
                          HeroMode(enabled: !MediaQuery.disableAnimationsOf(context),
                            child: Hero(tag: 'now-playing-art:${track.id}', child: _PlayerArtwork(
                            playing: playing,
                            artworkUrl: track.artworkUrl,
                            fallbackColor: theme.bzText2,
                          ))),
                        if (!_lyricsFocus) const Spacer(),
                        if (_lyricsFocus)
                          Expanded(
                            child: _LyricsView(
                              lyrics: _lyrics,
                              mode: _lyricsMode,
                              position: player.position,
                              focusMode: true,
                            ),
                          ),
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
                        if (player.playbackState == PlaybackState.failed)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text('Audio unavailable for this recording. Tap play to retry.',
                                style: theme.textTheme.bodySmall),
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
                                child: Semantics(
                                  label: 'Playback position',
                                  value: '${_format(player.position)} of ${_format(player.duration)}',
                                  child: Slider(
                                  value: player.duration > Duration.zero
                                      ? player.position.inMilliseconds
                                          .clamp(
                                              0, player.duration.inMilliseconds)
                                          .toDouble()
                                      : 0,
                                  max: player.duration.inMilliseconds > 0
                                      ? player.duration.inMilliseconds.toDouble()
                                      : 1,
                                  onChanged: (v) {

                                    controller.seekTo(
                                        Duration(milliseconds: v.toInt()));
                                  },
                                  semanticFormatterCallback: (v) =>
                                      _format(Duration(milliseconds: v.toInt())),
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_format(player.position),
                                      style: TextStyle(
                                          fontSize: BzType.caption,
                                          color: theme.bzText2)),
                                  Text('-${_format(player.duration > player.position ? player.duration - player.position : Duration.zero)}',
                                      style: TextStyle(
                                          fontSize: BzType.caption,
                                          color: theme.bzText2)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        BzTransportControls(
                          playing: playing,
                          onPrevious: controller.previous,
                          onNext: controller.next,
                          onTogglePlayPause: controller.togglePlayPause,
                          onShuffle: controller.toggleShuffle,
                          onRepeat: controller.cycleRepeat,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {

                                setState(() {
                                  _lyricsVisible = !_lyricsVisible;
                                  if (!_lyricsVisible) _lyricsFocus = false;
                                });
                              },
                              icon: BzSvgIcon(name: 'lyrics', size: 18),
                              label: Text(_lyricsVisible
                                  ? 'Hide Lyrics'
                                  : 'Show Lyrics'),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: _lyricsFocus
                                  ? 'Show artwork'
                                  : 'Focus lyrics',
                              icon: BzSvgIcon(
                                name: _lyricsFocus ? 'album' : 'lyrics',
                                size: 20,
                              ),
                              onPressed: () {

                                setState(() {
                                  _lyricsFocus = !_lyricsFocus;
                                  if (_lyricsFocus) {
                                    _lyricsVisible = true;


                                  }
                                });

                              },
                            ),
                            TextButton.icon(
                              onPressed: _openPlayingNext,
                              icon: BzSvgIcon(name: 'queue', size: 18),
                              label: const Text('Playing Next'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (!_lyricsFocus)
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
                  );
                }),
              ),
            ),
        ),
      ),
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  final bool playing;
  final String? artworkUrl;
  final Color fallbackColor;

  const _PlayerArtwork({
    required this.playing,
    required this.artworkUrl,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    return LayoutBuilder(
      builder: (context, constraints) {
        final heightCap = (MediaQuery.sizeOf(context).height * 0.43)
            .clamp(144.0, 420.0).toDouble();
        final side = (constraints.maxWidth * 0.72)
            .clamp(144.0, heightCap)
            .toDouble();
        return AnimatedScale(
          scale: playing ? 1.0 : 0.88,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero : const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(BzRadius.artwork),
              // Gentle lift: --shadow-glass-soft, never a hard drop shadow.
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 32,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BzRadius.artwork),
              child: artworkUrl != null
                  ? Image.network(
                      artworkUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: BzBnoteMark(
                            size: 96, color: fallbackColor),
                      ),
                    )
                  : Center(
                      child:
                          BzBnoteMark(size: 96, color: fallbackColor),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Lyrics with depth-of-field: the active line is bold and fully opaque,
/// surrounding lines fall back through two levels of softness — the
/// Apple Music karaoke treatment where focus tracks the voice.
class _LyricsView extends ConsumerWidget {
  final Lyrics? lyrics;
  final String mode;
  final Duration position;
  final bool focusMode;

  const _LyricsView({
    required this.lyrics,
    required this.mode,
    required this.position,
    this.focusMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);

    if (mode == 'loading') {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BzSkeleton(width: 220, height: 14, radius: 5),
          SizedBox(height: 14),
          BzSkeleton(width: 280, height: 14, radius: 5),
          SizedBox(height: 14),
          BzSkeleton(width: 190, height: 14, radius: 5),
        ],
      );
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
      padding: EdgeInsets.fromLTRB(24, focusMode ? 28 : 8, 24, 24),
      itemCount: lyrics!.lines.length,
      itemBuilder: (context, i) {
        final line = lyrics!.lines[i];
        final active = i == activeIndex;
        final activeWord =
            active && isSynced ? lyrics!.activeWordIndex(i, position) : -1;

        // Depth-of-field: distance from the active line sets softness.
        final distance = (i - activeIndex).abs();
        final Color lineColor;
        final FontWeight lineWeight;
        if (active) {
          lineColor = theme.bzText1;
          lineWeight = FontWeight.w700;
        } else if (highContrast) {
          // Preserve Apple's lyric hierarchy using weight, not low-
          // contrast translucency, when the OS requests stronger contrast.
          lineColor = theme.bzText2;
          lineWeight = FontWeight.w500;
        } else if (distance <= 1) {
          lineColor = theme.bzText2;
          lineWeight = FontWeight.w600;
        } else if (distance <= 3) {
          lineColor = theme.bzText2.withValues(alpha: 0.7);
          lineWeight = FontWeight.w400;
        } else {
          lineColor = theme.bzText2.withValues(alpha: 0.45);
          lineWeight = FontWeight.w400;
        }

        Widget seekable(Widget child) {
          if (!isSynced) return child;
          void seek() {
            ref.read(playerControllerProvider.notifier).seekTo(line.start);
          }
          return Semantics(
            button: true,
            label: 'Jump to lyric: ${line.text}',
            onTap: seek,
            child: InkWell(
              onTap: seek,
              excludeFromSemantics: true,
              child: ExcludeSemantics(child: child),
            ),
          );
        }
        if (line.words.isEmpty) {
          return seekable(Padding(
            padding: EdgeInsets.symmetric(vertical: focusMode ? 12 : 6),
            child: AnimatedDefaultTextStyle(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: focusMode ? BzType.title1 : BzType.headline,
                fontWeight: lineWeight,
                color: lineColor,
              ),
              child: Text(line.text),
            ),
          ));
        }

        return seekable(Padding(
          padding: EdgeInsets.symmetric(vertical: focusMode ? 12 : 6),
          child: Wrap(
            children: [
              for (var w = 0; w < line.words.length; w++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AnimatedDefaultTextStyle(
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: focusMode ? BzType.title1 : BzType.headline,
                      fontWeight: lineWeight,
                      color: active
                          ? (w <= activeWord
                              ? theme.bzText1
                              : theme.bzText2)
                          : lineColor,
                    ),
                    child: Text(line.words[w].text),
                  ),
                ),
            ],
          ),
        ));
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
    final value =
        await ref.read(favoritesStoreProvider).isFavorite(widget.track.id);
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
        content:
            Text(added ? 'Added to favorites' : 'Removed from favorites'),
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
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: upcoming.length,
                      onReorderItem: (oldIndex, newIndex) {
                        // Flutter now provides the post-removal target index.
                        // Do not decrement it a second time.
                        queue.reorderUpNext(
                          upcoming[oldIndex].entryId,
                          newIndex,
                        );
                      },
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
                            leading:
                                BzBnoteMark(size: 40, color: theme.bzText2),
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Remove from queue',
                                  onPressed: () => queue.remove(entry.entryId),
                                  icon: BzSvgIcon(
                                    name: 'close',
                                    color: theme.bzText2,
                                    size: 18,
                                  ),
                                ),
                                Tooltip(
                                  message: 'Drag to reorder',
                                  child: ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Icon(Icons.drag_handle,
                                          color: theme.bzText2),
                                    ),
                                  ),
                                ),
                              ],
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
