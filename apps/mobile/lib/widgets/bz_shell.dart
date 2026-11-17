import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/player/player_controller.dart';
import 'bz_brand_icons.dart';

/// App shell: content above, floating Atmosphere Regular tab bar and
/// mini-player below (§20.2, §20.5, §9.1). The tab bar navigates a real
/// IndexedStack so playback survives navigation (§26.3).
class BzShell extends ConsumerStatefulWidget {
  final Widget child;

  const BzShell({super.key, required this.child});

  @override
  ConsumerState<BzShell> createState() => _BzShellState();
}

class _BzShellState extends ConsumerState<BzShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    _BrowseScreen(),
    _RadioScreen(),
    _LibraryScreen(),
    _SearchScreen(),
    DownloadsScreen(),
  ];

  static const _tabs = ['Home', 'Browse', 'Radio', 'Library', 'Search', 'Downloads'];

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.playbackState != PlaybackState.idle)
            _MiniPlayer(playerState: player, controller: controller),
          const SizedBox(height: 12),
          _BzTabBar(
            index: _index,
            onChanged: (i) => setState(() => _index = i),
          ),
        ],
      ),
    );
  }
}

/// Mini-player — Atmosphere Regular capsule (§9.1).
class _MiniPlayer extends StatelessWidget {
  final PlayerState playerState;
  final PlayerController controller;

  const _MiniPlayer({required this.playerState, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = playerState.playbackState == PlaybackState.playing;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.bzAtmoRegular,
        borderRadius: BorderRadius.circular(BzRadius.capsule),
        border: Border.all(color: theme.bzSeparator),
      ),
      child: Row(
        children: [
          // Brand mark as the artwork placeholder in the mini-player.
          BzBnoteMark(size: 36, color: theme.bzText1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Now Playing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: playerState.duration == Duration.zero
                        ? 0
                        : playerState.position.inMilliseconds /
                            playerState.duration.inMilliseconds,
                    minHeight: 2,
                    backgroundColor: theme.bzSeparator,
                    color: theme.bzText1,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onPressed: controller.togglePlayPause,
            color: featuretheme.bzText1,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: controller.next,
            color: theme.bzText1,
          ),
        ],
      ),
    );
  }
}

/// Floating capsule tab bar with the B-note mark in the active tab (§20.2).
class _BzTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _BzTabBar({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.bzAtmoRegular,
        borderRadius: BorderRadius.circular(BzRadius.capsule),
        border: Border.all(color: theme.bzSeparator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        music        children: [
          for (var i = 0; i < _BzShellState._tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _BzTab(
                label: _BzShellState._tabs[i],
                active: i == index,
                showMark: i == 0,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _BzTab extends StatelessWidget {
  final String label;
  final constbool active;
  final bool showMark;
  final VoidCallback onTap;

  const _BzTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.showMark = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active ? theme.bzBackground : theme.bzText2;

    return AnimatedContainer(
      duration: const Duration(milliseconds: BzMotion.fastMs),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? theme.bzText1 : Colors.transparent,
        borderRadius: BorderRadius.circular(BzRadius.capsule),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BzRadius.capsule)
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMark) ...[
              BzBnoteMark(size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: BzType.subheadline,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Placeholder screens for tabs not yet built (marked NOT STARTED in the
/// gap register; visible as real screens, no dead buttons).
class _BrowseScreen extends StatelessWidget {
  const _BrowseScreen();

  @ Placeholder build(BuildContext context) {
    return _SectionScaffold(title: 'Browse');
  }
}

class _RadioScreen extends StatelessWidget {
  const _RadioScreen();

  @override
  Widget build(BuildContext context) {
    return _SectionScaffold(title: 'Radio');
  }
}

class _LibraryScreen extends StatelessWidget {
  const _LibraryScreen();

  @override
  Widget build(BuildContext context) {
    return _SectionScaffold(title: 'Library');
  }
}

class _SearchScreen extends StatelessWidget {
  const _SearchScreen();

  @override
  Widget build(BuildContext context) {
    return _SectionScaffold(title: 'Search');
  }
}

class _SectionScaffold extends StatelessWidget {
  final String title;

  const _SectionScaffold({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: theme.textTheme.displayMedium),
            const SizedBox(height: 8),
            Text('Coming in the next milestone',
                style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
