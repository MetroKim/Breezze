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
    this.artworkUrl,
    required this.onTap,
  });

  final String label;
  final String description;
  final String iconName;
  /// Real provider image only; an absent image retains the restrained
  /// elevated OLED tile instead of an invented or stock artist portrait.
  final String? artworkUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = artworkUrl == null ? null : Uri.tryParse(artworkUrl!);
    final showArtwork = uri != null &&
        uri.scheme == 'https' && uri.host.isNotEmpty;
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
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (showArtwork)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(BzRadius.card),
                      child: Image.network(
                        artworkUrl!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            ColoredBox(color: theme.bzSurface1),
                      ),
                    ),
                  ),
                if (showArtwork)
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xE6000000),
                            Color(0x7D000000),
                            Color(0x65000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
