import 'dart:async';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/audio/youtube_player_handoff.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import 'official_youtube_queue_policy.dart';

/// In-app official YouTube video player. This is video playback only; it does
/// not provide an audio-only stream, ad removal, background audio or downloads.
///
/// If YouTube prevents embedding, the user may explicitly open the original
/// watch page in YouTube. Breezze must not circumvent uploader restrictions.
class OfficialMusicVideoScreen extends ConsumerStatefulWidget {
  final String videoId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final List<OfficialYouTubeQueueEntry> foregroundQueue;

  const OfficialMusicVideoScreen({
    super.key,
    required this.videoId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.foregroundQueue = const [],
  });

  @override
  ConsumerState<OfficialMusicVideoScreen> createState() =>
      _OfficialMusicVideoScreenState();
}

class _OfficialMusicVideoScreenState
    extends ConsumerState<OfficialMusicVideoScreen> with WidgetsBindingObserver {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _playerEvents;
  String? _autoAdvancedVideoId;
  late String _currentVideoId;
  late String _currentTitle;
  late String _currentArtist;
  String? _currentArtworkUrl;

  // Provider recommendations are a foreground video watch list only.
  List<Map<String, String?>> _watchQueue = [];
  int _queuePosition = 0;

  bool get _valid =>
      YoutubePlayerHandoff.isValidProviderTrackId(_currentVideoId);

  Future<void> _loadWatchQueue() async {
    if (!_valid) return;
    if (widget.foregroundQueue.isNotEmpty) {
      final owned = normalizedOfficialYouTubeQueue(
        widget.foregroundQueue, selectedVideoId: widget.videoId,
      );
      if (owned.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _watchQueue = [
            for (final item in owned)
              {
                'videoId': item.videoId,
                'title': item.title,
                'artist': item.artist,
                'artworkUrl': item.artworkUrl,
              },
          ];
          _queuePosition = owned.indexWhere((item) => item.videoId == widget.videoId);
        });
        return;
      }
    }
    try {
      final result = await ref.read(authSessionProvider.notifier).api
          .ytMusicWatchQueue(widget.videoId);
      if (!mounted || result['kind'] != 'ok') return;
      final payload = result['value'];
      if (payload is! Map || payload['playbackAvailable'] != false ||
          payload['seedVideoId'] != widget.videoId ||
          payload['tracks'] is! List) return;
      final queue = <Map<String, String?>>[
        {
          'videoId': widget.videoId,
          'title': widget.title,
          'artist': widget.artist,
          'artworkUrl': widget.artworkUrl,
        },
      ];
      final seen = <String>{widget.videoId};
      for (final item in (payload['tracks'] as List).take(25)) {
        if (item is! Map) continue;
        final id = item['providerTrackId'];
        final title = item['title'];
        if (id is! String || title is! String ||
            !YoutubePlayerHandoff.isValidProviderTrackId(id) ||
            title.trim().isEmpty || !seen.add(id)) continue;
        queue.add({
          'videoId': id,
          'title': title,
          'artist': item['artist'] is String
              ? item['artist'] as String : 'Unknown artist',
          'artworkUrl': item['artworkUrl'] is String
              ? item['artworkUrl'] as String : null,
        });
      }
      if (mounted) setState(() => _watchQueue = queue);
    } catch (_) {
      // Unofficial queue failure must not prevent the official video player.
    }
  }

  // Advance only while the official player remains visible. Never use an
  // invisible audio-only background player or replay stale ended events.
  void _onPlayerValue(YoutubePlayerValue value) {
    if (!mounted) return;
    final currentId = _currentVideoId;
    final next = nextForegroundYouTubeQueueIndex(
      videoEnded: value.playerState == PlayerState.ended,
      playerVisible:
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      currentVideoId: currentId,
      reportedVideoId: value.metaData.videoId,
      currentIndex: _queuePosition,
      queueLength: _watchQueue.length,
    );
    if (next == null || _autoAdvancedVideoId == currentId) return;
    _autoAdvancedVideoId = currentId;
    unawaited(_jumpToQueueItem(next));
  }

  Future<void> _jumpToQueueItem(int position) async {
    if (position < 0 || position >= _watchQueue.length) return;
    final item = _watchQueue[position];
    final id = item['videoId'];
    if (id == null || !YoutubePlayerHandoff.isValidProviderTrackId(id)) return;
    try {
      if (_controller == null) {
        final opened = await YoutubePlayerHandoff.openProviderTrackId(id);
        if (!opened) return;
      } else {
        // This user-initiated action uses the official visible iframe,
        // never a detached, audio-only or background media URL.
        await _controller!.loadVideoById(videoId: id);
      }
      if (!mounted) return;
      setState(() {
        _queuePosition = position;
        _currentVideoId = id;
        _currentTitle = item['title'] ?? _currentTitle;
        _currentArtist = item['artist'] ?? _currentArtist;
        _currentArtworkUrl = item['artworkUrl'];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This YouTube video cannot be opened.')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentVideoId = widget.videoId;
    _currentTitle = widget.title;
    _currentArtist = widget.artist;
    _currentArtworkUrl = widget.artworkUrl;
    if (_valid &&
        YoutubePlayerHandoff.supportsEmbeddedPlayer(
          platform: defaultTargetPlatform,
          isWeb: kIsWeb,
        )) {
      // The visible official iframe is deliberately *not* auto-played.
      // Listeners control the video in the YouTube UI and all restrictions
      // remain enforced by the upstream provider.
      _controller = YoutubePlayerController.fromVideoId(
        videoId: _currentVideoId,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
        ),
      );
      _playerEvents = _controller!.stream.listen(_onPlayerValue);
    }
    // Queue metadata is optional; it never holds up the first video.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadWatchQueue();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pauseVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_playerEvents?.cancel());
    _controller?.close();
    super.dispose();
  }

  Future<void> _openOnYouTube() async {
    try {
      final opened =
          await YoutubePlayerHandoff.openProviderTrackId(_currentVideoId);
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
          const SnackBar(content: Text('Invalid or unavailable YouTube video.'))
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
        title: const Text('YouTube player'),
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
                          if (_currentArtworkUrl != null)
                            Image.network(
                              _currentArtworkUrl!,
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
                  _currentTitle,
                  style: theme.textTheme.headlineSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _currentArtist,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.bzText2,
                  ),
                ),
                if (_watchQueue.length > 1) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous YouTube video',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _queuePosition == 0
                            ? null : () => _jumpToQueueItem(_queuePosition - 1),
                      ),
                      Expanded(
                        child: Text(
                          'Up Next · ${_queuePosition + 1} of ${_watchQueue.length}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next YouTube video',
                        icon: const Icon(Icons.skip_next),
                        onPressed: _queuePosition + 1 >= _watchQueue.length
                            ? null : () => _jumpToQueueItem(_queuePosition + 1),
                      ),
                    ],
                  ),
                ],
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
