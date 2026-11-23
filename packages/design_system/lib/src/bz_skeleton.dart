import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';

/// Shared loading primitives for Breezze content surfaces.
///
/// The shimmer is intentionally subtle and uses the active semantic palette.
/// It stops when the platform requests reduced motion.
class BzSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;

  const BzSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 10,
    this.circle = false,
  });

  @override
  State<BzSkeleton> createState() => _BzSkeletonState();
}

class _BzSkeletonState extends State<BzSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    final shape = widget.circle
        ? BoxShape.circle
        : BoxShape.rectangle;
    final radius = widget.circle
        ? null
        : BorderRadius.circular(widget.radius);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shift = MediaQuery.disableAnimationsOf(context)
            ? 0.0
            : (_controller.value * 2.4) - 1.2;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(shift - 1, 0),
            end: Alignment(shift + 1, 0),
            colors: [
              colors.surface2,
              Color.lerp(colors.surface2, colors.elevated, 0.72)!,
              colors.surface2,
            ],
            stops: const [0.15, 0.5, 0.85],
          ).createShader(bounds),
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: colors.surface2,
          shape: shape,
          borderRadius: radius,
        ),
      ),
    );
  }
}

/// Artwork + two text lines + trailing metadata, matching Breezze track rows.
class BzSkeletonTrackRow extends StatelessWidget {
  final double artworkSize;
  final bool showTrailing;

  const BzSkeletonTrackRow({
    super.key,
    this.artworkSize = 52,
    this.showTrailing = true,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          BzSkeleton(
            width: artworkSize,
            height: artworkSize,
            radius: 9,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BzSkeleton(width: 164, height: 13, radius: 5),
                SizedBox(height: 8),
                BzSkeleton(width: 112, height: 10, radius: 4),
              ],
            ),
          ),
          if (showTrailing) ...[
            const SizedBox(width: 12),
            const BzSkeleton(width: 28, height: 28, radius: 14),
          ],
        ],
      );
}

/// Responsive artwork card skeleton for horizontal rails and discovery grids.
class BzSkeletonArtworkCard extends StatelessWidget {
  final double width;
  final double artworkHeight;

  const BzSkeletonArtworkCard({
    super.key,
    this.width = 156,
    this.artworkHeight = 156,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BzSkeleton(
              width: width,
              height: artworkHeight,
              radius: 12,
            ),
            const SizedBox(height: 10),
            const BzSkeleton(width: 118, height: 12, radius: 4),
            const SizedBox(height: 7),
            const BzSkeleton(width: 86, height: 10, radius: 4),
          ],
        ),
      );
}

/// A responsive grid of artwork placeholders. The caller supplies the
/// available width, so it works on phones, tablets and desktop windows.
class BzSkeletonArtworkGrid extends StatelessWidget {
  final int itemCount;
  final double minCardWidth;
  final double spacing;

  const BzSkeletonArtworkGrid({
    super.key,
    this.itemCount = 6,
    this.minCardWidth = 148,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / (minCardWidth + spacing))
              .floor()
              .clamp(1, 6);
          final width = (constraints.maxWidth -
                  (columns - 1) * spacing) /
              columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing + 4,
            children: List.generate(
              itemCount,
              (_) => BzSkeletonArtworkCard(
                width: width,
                artworkHeight: width,
              ),
            ),
          );
        },
      );
}
