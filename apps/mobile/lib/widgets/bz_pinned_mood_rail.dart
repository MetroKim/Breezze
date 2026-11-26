import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Pinned Home discovery filters shared by every device size.
///
/// Source UI pattern: a permanent, horizontally scrollable mood rail below
/// the collapsing masthead. Breezze owns the implementation and branding;
/// each mood must open a real search instead of changing a decorative chip.
class BzPinnedMoodRail extends StatelessWidget {
  const BzPinnedMoodRail({
    super.key,
    required this.moods,
    required this.onMoodSelected,
  });

  final List<String> moods;
  final ValueChanged<String> onMoodSelected;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedMoodDelegate(
        moods: moods,
        onMoodSelected: onMoodSelected,
      ),
    );
  }
}

class _PinnedMoodDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedMoodDelegate({
    required this.moods,
    required this.onMoodSelected,
  });

  final List<String> moods;
  final ValueChanged<String> onMoodSelected;

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.bzBackground.withValues(
            alpha: highContrast ? 1 : 0.98,
          ),
          border: Border(
            bottom: BorderSide(
              color: overlapsContent ? theme.bzSeparator : Colors.transparent,
              width: 0.5,
            ),
          ),
        ),
        child: Semantics(
          container: true,
          label: 'Browse music by mood',
          child: ListView.separated(
            key: const Key('breezze-pinned-mood-rail'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: moods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => BzFilterPill(
              label: moods[index],
              active: false,
              onTap: () => onMoodSelected(moods[index]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedMoodDelegate oldDelegate) =>
      oldDelegate.moods != moods ||
      oldDelegate.onMoodSelected != onMoodSelected;
}
