import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';

/// Shared Breezze cinematic atmosphere for Now Playing and artist details.
///
/// Incorporates the blurred artwork / soft mesh-like colour layering from the
/// supplied Flutter design reference without importing its mock player,
/// hardcoded catalog or duplicate theme. Artwork remains underneath a readable
/// high-contrast veil, and the single global player remains authoritative.
class BzAmbientBackdrop extends StatelessWidget {
  final Widget child;
  final String? artworkUrl;

  const BzAmbientBackdrop({
    super.key,
    required this.child,
    this.artworkUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bz;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasArtwork = artworkUrl != null &&
        artworkUrl!.trim().isNotEmpty &&
        !MediaQuery.highContrastOf(context);
    final blurArtwork = hasArtwork && !MediaQuery.disableAnimationsOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.background),
        // Crossfade between actual current-track covers. Keep one blur
        // surface and disable motion entirely for accessibility requests.
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 420),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          child: hasArtwork
              ? Image.network(
                  artworkUrl!,
                  key: ValueKey(artworkUrl),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox.expand(),
                )
              : const SizedBox.expand(key: ValueKey('oled-no-artwork')),
        ),
        // One backdrop blur rather than overlapping filtered circles.
        // The artwork supplies the track/artist-specific colour palette.
        if (blurArtwork)
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 54, sigmaY: 54),
            child: const ColoredBox(color: Colors.transparent),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.46, 1],
              colors: [
                colors.background.withValues(alpha: dark ? 0.40 : 0.64),
                colors.background.withValues(alpha: dark ? 0.73 : 0.84),
                colors.background,
              ],
            ),
          ),
        ),
        // Multiple soft radial washes reproduce the reference's mesh-like
        // depth without fabricating a separate artwork palette or source.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.85, -0.55),
              radius: 1.4,
              colors: [
                colors.surface2.withValues(alpha: dark ? 0.17 : 0.24),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.0, 0.80),
              radius: 1.2,
              colors: [
                colors.accent.withValues(alpha: dark ? 0.06 : 0.045),
                Colors.transparent,
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
