import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/bootstrap.dart';
import '../app/downloads_controller.dart';
import '../core/audio/background_audio.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/now_playing_screen.dart';
import '../features/player/player_controller.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'bz_brand_icons.dart';

/// App root: ProviderScope with the live resolver override + engine +
/// background audio.
class BreezzeShell extends StatelessWidget {
  const BreezzeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWith(
          (ref) => ref.watch(liveResolverProvider)),
    ]);

    attachPlaybackEngine(container);

    // Initialize the background-audio sync (noop bridge until native
    // audio_service lands; the seam is live).
    container.read(backgroundSyncProvider);

    return UncontrolledProviderScope(
      container: container,
      child: const BreezzeApp(),
    );
  }
}

class BreezzeApp extends StatelessWidget {
  const BreezzeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breezze',
      debugShowCheckedModeBanner: false,
      theme: bzLightTheme(),
      darkTheme: bzDarkTheme(),
      home: const BzHome(),
    );
  }
}

class BzHome extends ConsumerStatefulWidget {
  const BzHome({super.key});

  @override
  ConsumerState<BzHome> createState() => _BzHomeState();
}

class _BzHomeState extends ConsumerState<BzHome> {
  int _index = 0;

  static const _tabs = ['Home', 'Search', 'Library', 'Downloads', 'Settings'];

  @override
  void initState() {
    super.initState();
    // The home tab listens to the first-run hint (Search nudge).
    ref.listenManual(homeTabHintProvider, (prev, next) {
      if (next > 0) setState(() => _index = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          SearchScreen(),
          LibraryScreen(),
          DownloadsScreen(),
          SettingsScreen(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.playbackState != PlaybackState.idle)
            _MiniPlayer(onTap: _openNowPlaying),
          const SizedBox(height: 12),
          _TabBar(index: _index, onChanged: (i) => setState(() => _index = i)),
        ],
      ),
    );
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NowPlayingScreen(),
        fullscreenDialog: true,
      ),
    );
  }
}

class _MiniPlayer extends ConsumerWidget {
  final VoidCallback onTap;

  const _MiniPlayer({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final theme = Theme.of(context);
    final playing = player.playbackState == PlaybackState.playing;
    final track = player.currentTrack;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.bzAtmoRegular,
          borderRadius: BorderRadius.circular(BzRadius.capsule),
          border: Border.all(color: theme.bzSeparator),
        ),
        child: Row(
          children: [
            track?.artworkUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      track!.artworkUrl!,
                      width: 36,
                      height: 36,
                      errorBuilder: (_, __, ___) =>
                          BzBnoteMark(size: 36, color: theme.bzText1),
                    ),
                  )
                : BzBnoteMark(size: 36, color: theme.bzText1),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(track?.title ?? 'Now Playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium),
                  if (player.duration > Duration.zero)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: player.position.inMilliseconds /
                            player.duration.inMilliseconds,
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
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _TabBar({required this.index, required this.onChanged});

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
          for (var i = 0; i < _BzHomeState._tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _Tab(
                label: _BzHomeState._tabs[i],
                active: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active ? theme.bzBackground : theme.bzText2;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: BzMotion.fastMs),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.bzText1 : Colors.transparent,
          borderRadius: BorderRadius.circular(BzRadius.capsule),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: BzType.subheadline,
                fontWeight: FontWeight.w600,
                color: fg)),
      ),
    );
  }
}
