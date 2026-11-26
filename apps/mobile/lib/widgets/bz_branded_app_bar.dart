import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_morphing_brand_header.dart';

/// One Breezze-branded toolbar for all new secondary/catalog screens.
///
/// The product brand is always Breezze; provider names (e.g. YouTube Music)
/// are displayed as source labels, never as replacement app identity.
/// Keep native back navigation, keyboard semantics and a single toolbar.
class BzBrandedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BzBrandedAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final condensed = MediaQuery.textScalerOf(context).scale(1) >= 1.4 ||
        MediaQuery.sizeOf(context).width < 380;
    return AppBar(
      toolbarHeight: preferredSize.height,
      automaticallyImplyLeading: leading == null,
      leading: leading,
      titleSpacing: 10,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BzCompactBrandMark(size: 34),
          const SizedBox(width: 10),
          Flexible(
            child: Semantics(
              header: true,
              label: 'Breezze, $title${subtitle == null ? '' : ', $subtitle'}',
              child: ExcludeSemantics(
                child: condensed
                    ? Text(
                        'Breezze · $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Breezze',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.bzAccent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.bzText2,
                    ),
                  ),
              ],
            ),
              ),
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}
