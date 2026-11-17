import 'package:flutter/material.dart';

import 'bz_theme.dart';

/// BzAmbientBackdrop — content is the colour (Liner principle, Breezze
/// execution). Artwork blooms softly behind the screen chrome.
///
/// The artwork image is blurred heavily; the base tint stays the theme
/// surface so text contrast never depends on artwork content.
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base: theme surface, always behind everything.
        Container(color: colors.background),
        // Ambient layer: heavily blurred artwork, low opacity.
        if (artworkUrl != null)
          Image.network(
            artworkUrl!,
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.35),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        // Blur scrim over the artwork.
        BackdropFilter(
          filter: _heavyBlur,
          child: Container(
            color: colors.background.withValues(alpha: 0.55),
          ),
        ),
        child,
      ],
    );
  }
}

const _heavyBlur = kBlur60;

const kBlur60 = ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60);
