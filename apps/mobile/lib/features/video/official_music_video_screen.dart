import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/audio/youtube_player_handoff.dart';
import '../../widgets/bz_brand_icons.dart';

/// In-app official YouTube video player. This is video playback only; it does
/// not provide an audio-only stream, ad removal, background audio or downloads.
///
/// If YouTube prevents embedding, the user may explicitly open the original
/// watch page in YouTube. Breezze must not circumvent uploader restrictions.
class OfficialMusicVideoScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String artist;
  final String? artworkUrl;

  const OfficialMusicVideoScreen({
    super.key,
    required this.videoId,
    required this.title,
    required this.artist,
    this.artworkUrl,
  });

  @override
  State<OfficialMusicVideoScreen> createState() =>
      _OfficialMusicVideoScreenState();
}

class _OfficialMusicVideoScreenState
    extends State<OfficialMusicVideoScreen> {
  YoutubePlayerController? _controller;

  bool get _valid =>
      YoutubePlayerHandoff.isValidProviderTrackId(widget.videoId);

  @override
  void initState() {
    super.initState();
    if (_valid &&
        YoutubePlayerHandoff.supportsEmbeddedPlayer(
          platform: defaultTargetPlatform,
          isWeb: kIsWeb,
        )) {
      // The visible official iframe is deliberately *not* auto-played.
      // Listeners control the video in the YouTube UI and all restrictions
      // remain enforced by the upstream provider.
      _controller = YoutubePlayerController.fromVideoId(
        videoId: widget.videoId,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  Future<void> _openOnYouTube() async {
    try {
      final opened =
          await YoutubePlayerHandoff.openProviderTrackId(widget.videoId);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The official YouTube player could not be opened.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid or unavailable music video.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _screen(context, null);
    return YoutubePlayerScaffold(
      controller: controller,
      aspectRatio: 16 / 9,
      builder: (context, player) => _screen(context, player),
    );
  }

  Widget _screen(BuildContext context, Widget? embeddedPlayer) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: AppBar(
        title: const Text('Music Video'),
        leading: IconButton(
          tooltip: 'Back to music',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16, 12, 16,
                BzBreakpoints.bottomClearance(context, compact: 36),
              ),
              children: [
                if (embeddedPlayer != null)
                  embeddedPlayer
                else
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.bzSurface1,
                        borderRadius: BorderRadius.circular(BzRadius.card),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.artworkUrl != null)
                            Image.network(
                              widget.artworkUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.bzBackground.withValues(alpha: 0.58),
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  BzSvgIcon(
                                    name: 'video',
                                    color: theme.bzText1,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    !_valid
                                        ? 'Invalid video reference'
                                        : 'Embedded video is not available on this platform',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'The official YouTube watch page is available below.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                Text(
                  widget.title,
                  style: theme.textTheme.headlineSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.artist,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.bzText2,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    BzSvgIcon(name: 'info', color: theme.bzText2, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Official YouTube player. Playback, availability, ads '
                        'and video restrictions are controlled by YouTube.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.bzText2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _valid ? _openOnYouTube : null,
                    icon: const BzSvgIcon(
                      name: 'arrow-up-right',
                      size: 18,
                    ),
                    label: const Text('Open official YouTube page'),
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
