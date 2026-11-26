import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_brand_icons.dart';

/// Content-first Breezze music transport; playback commands remain callbacks
/// into the ONE PlayerController, never a second engine or hidden queue.
///
/// On compact widths / accessibility text sizes, the three primary transport
/// controls keep their Apple Music-inspired glass capsule. Secondary shuffle
/// and repeat move to the next row instead of overflowing or disappearing.
class BzTransportControls extends StatelessWidget {
  final bool playing;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  const BzTransportControls({
    super.key,
    required this.playing,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayPause,
    required this.onShuffle,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final shuffle = IconButton(
          tooltip: 'Shuffle',
          icon: const BzSvgIcon(name: 'shuffle'),
          onPressed: onShuffle,
          color: theme.bzText2,
        );
        final repeat = IconButton(
          tooltip: 'Repeat',
          icon: const BzSvgIcon(name: 'repeat'),
          onPressed: onRepeat,
          color: theme.bzText2,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BzGlassContainer(
              radius: BzRadius.capsule,
              blur: 18,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!compact) ...[
                      shuffle,
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: 'Previous track',
                      icon: const BzSvgIcon(name: 'skip-previous', size: 34),
                      onPressed: onPrevious,
                    ),
                    const SizedBox(width: 8),
                    _BzCircularPlaybackButton(
                      playing: playing,
                      size: 64,
                      onTap: onTogglePlayPause,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Next track',
                      icon: const BzSvgIcon(name: 'skip-next', size: 34),
                      onPressed: onNext,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      repeat,
                    ],
                  ],
                ),
              ),
            ),
            if (compact)
              // Do not hide secondary actions behind an inaccessible swipe
              // gesture: they stay visible, focusable and at least 44pt tall.
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [shuffle, repeat],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BzCircularPlaybackButton extends StatelessWidget {
  final bool playing;
  final double size;
  final VoidCallback onTap;

  const _BzCircularPlaybackButton({
    required this.playing,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: playing ? 'Pause playback' : 'Resume playback',
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          customBorder: const CircleBorder(),
          child: ExcludeSemantics(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: theme.bzText1,
                shape: BoxShape.circle,
              ),
              child: BzSvgIcon(
                name: playing ? 'pause' : 'play',
                color: theme.bzBackground,
                size: size * 0.42,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
