import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_player_pill.dart';
import 'bz_shell_nav.dart';
import '../features/browse/browse_screen.dart';
import '../features/radio/radio_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/now_playing_screen.dart';
import '../features/player/player_controller.dart';
import '../features/search/search_screen.dart';

/// Route observer shared with BreezzeAppRoot's MaterialApp. The shell
/// subscribes so its glass surfaces can demote to solids while a
/// fullscreen route (Now Playing) covers them — the viewport blur budget
/// of 2 stays honest across route transitions.
final RouteObserver<PageRoute<dynamic>> bzRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Breezze's five-destination Liquid Glass shell.
///
/// Shell contract (§4.1/§4.2):
/// - >=1200px: 260px glass sidebar + main + floating player pill
///   (bottom: 20, centered).
/// - 810–1199px: sidebar collapses to a 72px icon rail.
/// - <810px: sidebar becomes a glass bottom tab bar; the player pill
///   docks to the bottom safe area with 16px horizontal margins.
///
/// Downloads live inside Library; Settings are reached from the profile
/// surface; neither is a top-level tab.
class BreezzeShell extends StatelessWidget {
  const BreezzeShell({super.key});

  @override
  Widget build(BuildContext context) => const _BreezzeRoot();
}

class _BreezzeRoot extends StatefulWidget {
  const _BreezzeRoot();

  @override
  State<_BreezzeRoot> createState() => _BreezzeRootState();
}

class _BreezzeRootState extends State<_BreezzeRoot> with RouteAware {
  bool _shellIsCurrent = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      bzRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    bzRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => _update(true);

  @override
  void didPushNext() => _update(false);

  @override
  void didPop() => _update(true);

  @override
  void didPopNext() => _update(true);

  void _update(bool current) {
    if (_shellIsCurrent == current) return;
    setState(() => _shellIsCurrent = current);
  }

  @override
  Widget build(BuildContext context) =>
      _BzHome(shellIsCurrent: _shellIsCurrent);
}

class _BzHome extends ConsumerStatefulWidget {
  final bool shellIsCurrent;

  const _BzHome({required this.shellIsCurrent});

  @override
  ConsumerState<_BzHome> createState() => _BzHomeState();
}

class _BzHomeState extends ConsumerState<_BzHome> {
  int _index = 0;

  static const _tabs = [
    BzTabDestination('Home', 'assets/icons/home.svg'),
    BzTabDestination('Browse', 'assets/icons/browse.svg'),
    BzTabDestination('Radio', 'assets/icons/radio.svg'),
    BzTabDestination('Library', 'assets/icons/library.svg'),
    BzTabDestination('Search', 'assets/icons/search.svg'),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeTabHintProvider, (previous, next) {
      if (next >= 0 && next < _tabs.length && next != _index) {
        setState(() => _index = next);
      }
    });
    final player = ref.watch(playerControllerProvider);
    final hasPlayer = player.playbackState != PlaybackState.idle;

    final pages = IndexedStack(
      index: _index,
      children: const [
        HomeScreen(),
        BrowseScreen(),
        RadioScreen(),
        LibraryScreen(),
        SearchScreen(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < BzBreakpoints.medium; // <810
        final rail = width >= BzBreakpoints.medium &&
            width < BzBreakpoints.expanded; // 810–1199

        if (compact) {
          // Phone: glass capsule tab bar at the bottom, player pill docked
          // above it with 16px horizontal margins (§4.2).
          return Scaffold(
            body: pages,
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPlayer) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal:
                              BzBreakpoints.playerPillHorizontalMargin,
                        ),
                        child: BzPlayerPill(
                          onTap: _openNowPlaying,
                          glass: widget.shellIsCurrent,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    BzTabBar(
                      index: _index,
                      tabs: _tabs,
                      glass: widget.shellIsCurrent,
                      onChanged: (i) => setState(() => _index = i),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Desktop/tablet: glass sidebar (or 72px rail) + content pane +
        // floating player pill anchored bottom: 20, centered — never a
        // docked bar (§4.1).
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    BzSidebarOrRail(
                      rail: rail,
                      index: _index,
                      tabs: _tabs,
                      glass: widget.shellIsCurrent,
                      onChanged: (i) => setState(() => _index = i),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: BzBreakpoints.contentMaxWidth,
                          ),
                          child: pages,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasPlayer)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: BzBreakpoints.playerPillBottomInset,
                  child: IgnorePointer(
                    ignoring: !widget.shellIsCurrent,
                    child: Opacity(
                      opacity: widget.shellIsCurrent ? 1 : 0,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: BzPlayerPill(
                          onTap: _openNowPlaying,
                          glass: widget.shellIsCurrent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
