import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_brand_icons.dart';

/// Provider-authored release cards. This is a *discovery* shelf, not a
/// playlist or a promise of licensed audio playback. No mock artists appear.
class BzReleaseShelf extends StatelessWidget {
  const BzReleaseShelf({
    super.key,
    required this.items,
    required this.onOpen,
  });

  /// Each item must contain a provider title, artist and HTTPS artwork URL.
  final List<Map<String, String>> items;
  final ValueChanged<Map<String, String>> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fresh releases', style: theme.textTheme.titleLarge),
        const SizedBox(height: 5),
        Text('Albums from the live music catalog',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
        const SizedBox(height: 14),
        SizedBox(
          height: (218 + (MediaQuery.textScalerOf(context).scale(1) - 1) * 46)
              .clamp(218.0, 310.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              final title = item['title'] ?? '';
              final artist = item['artist'] ?? '';
              final url = item['artworkUrl'] ?? '';
              return SizedBox(
                width: 156,
                child: Semantics(
                  button: true,
                  label: 'Explore $title by $artist',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(BzRadius.artwork),
                      onTap: () => onOpen(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(BzRadius.artwork),
                            child: SizedBox.square(
                              dimension: 156,
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: theme.bzSurface2,
                                  child: Center(
                                    child: BzBnoteMark(
                                      size: 34, color: theme.bzText2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          Text(artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.bzText2,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
