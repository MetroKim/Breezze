import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_brand_icons.dart';

/// One shell navigation destination.
class BzTabDestination {
  final String label;
  final String asset;
  const BzTabDestination(this.label, this.asset);
}

/// The 260px glass sidebar (>=1200px) or the 72px icon rail (810-1199px).
/// Selected rows use the quiet tint fill at 8px radius — never a filled
/// capsule at rest (§4.1).
class BzSidebarOrRail extends StatelessWidget {
  final bool rail;
  final int index;
  final List<BzTabDestination> tabs;
  final bool glass;
  final ValueChanged<int> onChanged;

  const BzSidebarOrRail({
    super.key,
    required this.rail,
    required this.index,
    required this.tabs,
    required this.glass,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (rail) {
      return SizedBox(
        width: BzBreakpoints.iconRailWidth,
        child: BzGlassMaterial(
          state: BzGlassState.pillScrolled,
          radius: 0,
          shadows: const [],
          reduceTransparency: !glass,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: BzBnoteMark(size: 26, color: theme.bzText1),
                  ),
                  for (var i = 0; i < tabs.length; i++)
                    BzRailTabButton(
                      destination: tabs[i],
                      active: index == i,
                      onTap: () => onChanged(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: BzBreakpoints.sidebarWidth,
      child: BzGlassMaterial(
        state: BzGlassState.pillScrolled,
        radius: 0,
        shadows: const [],
        reduceTransparency: !glass,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 28),
                  child: Row(
                    children: [
                      BzBnoteMark(size: 30, color: theme.bzText1),
                      const SizedBox(width: 10),
                      Text(
                        'Breezze',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < tabs.length; i++)
                  BzSidebarTabButton(
                    destination: tabs[i],
                    active: index == i,
                    onTap: () => onChanged(i),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'YOUR MUSIC. YOUR SPACE.',
                    style: TextStyle(
                      color: theme.bzText2,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon-rail tab: 44x44pt target (NFR-006), tooltip label.
class BzRailTabButton extends StatelessWidget {
  final BzTabDestination destination;
  final bool active;
  final VoidCallback onTap;

  const BzRailTabButton({
    super.key,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.bzAccent : theme.bzText2;
    return Semantics(
      button: true,
      selected: active,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: active ? theme.bzSurface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(BzRadius.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(BzRadius.button),
            onTap: onTap,
            child: SizedBox(
              width: BzSpacing.tapTarget,
              height: BzSpacing.tapTarget,
              child: Center(
                child: SvgPicture.asset(
                  destination.asset,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar tab with label.
class BzSidebarTabButton extends StatelessWidget {
  final BzTabDestination destination;
  final bool active;
  final VoidCallback onTap;

  const BzSidebarTabButton({
    super.key,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.bzAccent : theme.bzText2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: active,
        label: destination.label,
        child: Tooltip(
          message: destination.label,
          child: Material(
            color: active ? theme.bzSurface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(BzRadius.button),
            child: InkWell(
              borderRadius: BorderRadius.circular(BzRadius.button),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      destination.asset,
                      width: 21,
                      height: 21,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    ),
                    const SizedBox(width: 13),
                    Text(
                      destination.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone bottom tab bar — capsule glass (<810px).
class BzTabBar extends StatelessWidget {
  final int index;
  final List<BzTabDestination> tabs;
  final bool glass;
  final ValueChanged<int> onChanged;

  const BzTabBar({
    super.key,
    required this.index,
    required this.tabs,
    required this.glass,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (details) =>
              _selectFromGlobalX(details.globalPosition.dx, context),
          onLongPressMoveUpdate: (details) =>
              _selectFromGlobalX(details.globalPosition.dx, context),
          child: BzGlassMaterial(
            state: BzGlassState.pillScrolled,
            radius: BzRadius.pill,
            reduceTransparency: !glass,
            shadows: const [],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: BzTabButton(
                        destination: tabs[i],
                        active: i == index,
                        onTap: () => onChanged(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectFromGlobalX(double globalX, BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 24;
    final localX = (globalX - 12).clamp(0.0, width - 1);
    final next = (localX / (width / tabs.length)).floor();
    onChanged(next.clamp(0, tabs.length - 1).toInt());
  }
}

class BzTabButton extends StatelessWidget {
  final BzTabDestination destination;
  final bool active;
  final VoidCallback onTap;

  const BzTabButton({
    super.key,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.bzAccent : theme.bzText2;

    return Semantics(
      button: true,
      selected: active,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(BzRadius.button),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: BzMotion.fastMs),
                    curve: const Cubic(0.22, 1, 0.36, 1),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: active ? theme.bzSurface2 : Colors.transparent,
                      borderRadius: BorderRadius.circular(BzRadius.button),
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.asset(
                      destination.asset,
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
