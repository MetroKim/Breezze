import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/player/player_controller.dart';
import 'bz_brand_icons.dart';

/// App shell: content above, floating Atmosphere Regular tab bar and
/// mini-player below (§20.2, §20.5, §9.1).
class BzShell extends ConsumerWidget {
  final Widget child;

  const BzShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      body: child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.playbackState != PlaybackState.idle)
            _MiniPlayer(playerState: player, controller: controller),
          const SizedBox(height: 12),
          _BzTabBar(),
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
            color: theme.bzText1,
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
class _BzTabBar extends StatefulWidget {
  @override
  State<_BzTabBar> createState() => _BzTabBarState();
}

class _BzTabBarState extends State<_BzTabBar> {
  int _index = 0;

  static const _tabs = ['Home', 'Browse', 'Radio', 'Library', 'Search'];

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
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _BzTab(
                label: _tabs[i],
                active: i == _index,
                showMark: i == 0,
                onTap: () => setState(() => _index = i),
              ),
            ),
        ],
      ),
    );
  }
}

class _BzTab extends StatelessWidget {
  final String label;
  final bool active;
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
        borderRadius: BorderRadius.circular(BzRadius.capsule),
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
