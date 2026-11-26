import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_brand_icons.dart';

/// True only for routes actually rendered beside the persistent desktop
/// sidebar. Pushed search/detail routes do not inherit this scope and retain
/// their own Breezze identity even when the desktop window is wide.
class BzSidebarBrandOwner extends InheritedWidget {
  const BzSidebarBrandOwner({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool visibleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BzSidebarBrandOwner>()
          ?.visible ?? false;

  @override
  bool updateShouldNotify(covariant BzSidebarBrandOwner oldWidget) =>
      oldWidget.visible != visible;
}

/// The same original Breezze circular badge used in compact headers.
/// This is intentionally never the YouTube Music product mark.
class BzCompactBrandMark extends StatelessWidget {
  const BzCompactBrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Breezze',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('breezze-circular-mark'),
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: BzBnoteMark(size: size * 0.57, color: Colors.white),
        ),
      ),
    );
  }
}

/// Scroll-aware, pinned Breezze identity for discovery pages.
///
/// Recreates the useful *interaction pattern* of an expanding/collapsing
/// music-app masthead. The artwork, wordmark and code belong to Breezze.
/// The pill gently morphs into a black circular badge containing only our
/// own B-note mark. No YouTube Music trademarks or clone source are used.
class BzMorphingBrandHeader extends StatelessWidget {
  const BzMorphingBrandHeader({
    super.key,
    this.actions = const <Widget>[],
    this.sidebarBrandOnDesktop = false,
  });

  final List<Widget> actions;

  /// The desktop shell already contains the Breezze wordmark. Hide this
  /// page-level logo there to prevent duplicate branding in one viewport.
  final bool sidebarBrandOnDesktop;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _BzBrandHeaderDelegate(
        actions: actions,
        sidebarBrandOnDesktop: sidebarBrandOnDesktop,
      ),
    );
  }
}

class _BzBrandHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _BzBrandHeaderDelegate({
    required this.actions,
    required this.sidebarBrandOnDesktop,
  });

  final List<Widget> actions;
  final bool sidebarBrandOnDesktop;

  @override
  double get maxExtent => 94;

  @override
  double get minExtent => 62;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final compact = progress >= 0.55;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final background = theme.bzBackground;
    final width = 116 - progress * 72;
    // Very narrow phones/foldables need a functional, unclipped header.
    // Secondary settings are reachable through Account when hidden.
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final visibleActions = narrow && actions.length > 2
        ? <Widget>[actions.first, actions.last]
        : actions;
    final brandAlreadyInSidebar = sidebarBrandOnDesktop &&
        BzSidebarBrandOwner.visibleOf(context);

    // A pinned sliver must paint its full declared extent. Without the
    // expansion Flutter may measure the action row as 48dp while the sliver
    // advertises 94dp, violating layoutExtent <= paintExtent.
    return SizedBox.expand(
      child: DecoratedBox(
      decoration: BoxDecoration(
        color: background.withValues(
          alpha: highContrast ? 1.0 : 0.97,
        ),
        border: Border(
          bottom: BorderSide(
            color: overlapsContent || compact
                ? theme.bzSeparator
                : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (!brandAlreadyInSidebar) Semantics(
                label: 'Breezze',
                image: true,
                child: ExcludeSemantics(
                  child: AnimatedContainer(
                    key: const Key('breezze-morphing-brand'),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    width: width,
                    height: 44,
                    decoration: BoxDecoration(
                      color: compact ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(compact ? 22 : 8),
                      border: compact && highContrast
                          ? Border.all(color: Colors.white, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      child: compact
                          ? const BzBnoteMark(
                              key: Key('breezze-compact-icon'),
                              size: 25,
                              color: Colors.white,
                            )
                          : SizedBox(
                              key: const Key('breezze-expanded-wordmark'),
                              width: 106,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: BzRibbonLogo(
                                  width: 106,
                                  color: theme.bzText1,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              ...visibleActions,
            ],
          ),
        ),
      ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _BzBrandHeaderDelegate oldDelegate) =>
      oldDelegate.sidebarBrandOnDesktop != sidebarBrandOnDesktop ||
      oldDelegate.actions != actions;
}
