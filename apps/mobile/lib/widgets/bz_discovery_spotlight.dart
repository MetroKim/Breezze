import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Breezze's original discovery hero: editorial music browsing with a
/// restrained liquid-glass finish. It does not require an external UI clone,
/// new state framework, or unlicensed imagery.
class BzDiscoverySpotlight extends StatelessWidget {
  const BzDiscoverySpotlight({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.bzAccent;
    final highContrast = MediaQuery.highContrastOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(BzRadius.card),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: highContrast ? 0.05 : 0.20),
                    theme.bzSurface1,
                    theme.bzSurface2,
                  ],
                ),
              ),
            ),
          ),
          if (!highContrast && !reduceMotion)
            Positioned(
              right: -42,
              top: -68,
              child: IgnorePointer(
                child: Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.22),
                        accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          BzGlassContainer(
            radius: BzRadius.card,
            blur: 12,
            fillColor: theme.bzSurface1.withValues(alpha: 0.82),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 17, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          eyebrow.toUpperCase(),
                          maxLines: 2,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.bzText2,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.bzText1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.bzText2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
