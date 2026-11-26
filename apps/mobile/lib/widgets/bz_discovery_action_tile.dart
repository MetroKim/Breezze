import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_brand_icons.dart';

/// A genuine navigable section entrance; never a decorative fake "More".
/// Category tiles use inexpensive tinted solids, saving glass blur for the
/// pinned brand and featured discovery artwork.
class BzDiscoveryActionTile extends StatelessWidget {
  const BzDiscoveryActionTile({
    super.key,
    required this.label,
    required this.description,
    required this.iconName,
    required this.onTap,
  });

  final String label;
  final String description;
  final String iconName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: theme.bzSurface1,
        borderRadius: BorderRadius.circular(BzRadius.card),
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(BzRadius.card),
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BzRadius.card),
              border: Border.all(color: theme.bzSeparator, width: 0.5),
            ),
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BzSvgIcon(name: iconName, color: theme.bzAccent, size: 23),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.bzText2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                BzSvgIcon(name: 'chevron-right', color: theme.bzText2, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
