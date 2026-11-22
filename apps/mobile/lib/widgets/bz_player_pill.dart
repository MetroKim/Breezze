import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../features/player/player_controller.dart';

/// The floating player pill (§4.1) — the shell's premium signal.
///
/// Artwork thumbnail, track/artist info, transport controls, and the
/// progress hairline. Auto-width capsule (radius: pill), media-overlay
/// material when artwork backs it. Anchored bottom: 20, centered on
/// desktop; docked above the phone tab bar with 16px margins on compact.
/// Demotes to a solid capsule while a fullscreen route covers the shell.
class BzPlayerPill extends ConsumerWidget {
  final VoidCallback onTap;
  final bool glass;

  const BzPlayerPill({super.key, required this.onTap, required this.glass});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final theme = Theme.of(context);
    final playing = player.playbackState == PlaybackState.playing;
    final track = player.currentTrack;
    final progress = player.duration > Duration.zero
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -150) onTap();
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: BzGlassMaterial(
            state: BzGlassState.mediaOverlay,
            radius: BzRadius.pill,
            reduceTransparency: !glass,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BzRadius.artwork),
                        child: track?.artworkUrl != null
                            ? Image.network(
                                track!.artworkUrl!,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _MiniArtwork(color: theme.bzText2),
                              )
                            : _MiniArtwork(color: theme.bzText2),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track?.title ?? 'Now Playing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track?.artist ?? 'Breezze',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: BzType.footnote,
                                color: theme.bzText2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        tooltip: 'Previous track',
                        onPressed: controller.previous,
                        icon: SvgPicture.asset(
                          'assets/icons/skip-previous.svg',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                            theme.bzText1,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      _PillIconButton(
                        asset: playing
                            ? 'assets/icons/pause.svg'
                            : 'assets/icons/play.svg',
                        label: playing ? 'Pause' : 'Play',
                        onPressed: controller.togglePlayPause,
                      ),
                      _PillIconButton(
                        asset: 'assets/icons/skip-next.svg',
                        label: 'Next track',
                        onPressed: controller.next,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: theme.bzSeparator,
                      color: theme.bzAccent,
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

class _MiniArtwork extends StatelessWidget {
  final Color color;
  const _MiniArtwork({required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 42,
        height: 42,
        child: Center(
          child: SvgPicture.asset(
            'assets/icons/music-note.svg',
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      );
}

class _PillIconButton extends StatelessWidget {
  final String asset;
  final String label;
  final VoidCallback onPressed;

  const _PillIconButton({
    required this.asset,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: SvgPicture.asset(
        asset,
        width: 21,
        height: 21,
        colorFilter: ColorFilter.mode(
          Theme.of(context).bzText1,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
