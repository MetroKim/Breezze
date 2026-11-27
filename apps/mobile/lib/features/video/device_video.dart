import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'open_youtube_player.dart';
import 'video_source_policy.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_branded_app_bar.dart';

bool get supportsDeviceVideo => kIsWeb ||
    [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS].contains(defaultTargetPlatform);

Future<void> pickDeviceVideo(BuildContext context) async {
  if (!supportsDeviceVideo) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device video is not supported on this platform.')),
      );
    }
    return;
  }
  try {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'MP4 video', extensions: ['mp4', 'm4v'],
          mimeTypes: ['video/mp4'], uniformTypeIdentifiers: ['public.mpeg-4', 'com.apple.m4v-video']),
    ]);
    if (file == null || !context.mounted) return;
    await openVideoSurface(context, (_) => _DeviceVideo(file: file));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this video.')));
  }
}

/// Only signed Breezze R2 MP4 media, not raw YouTube media links.
Future<void> openAuthorizedBreezzeVideo(
  BuildContext context, {
  required Uri streamUrl,
  required String title,
}) async {
  final trustedOrigin = Uri.tryParse(configuredBreezzeVideoCdnOrigin);
  if (trustedOrigin == null ||
      !isValidBreezzeVideoStreamUrl(
        streamUrl, trustedOrigin: trustedOrigin,
      )) {
    throw ArgumentError.value(
      streamUrl, 'streamUrl', 'untrusted or expired Breezze video grant',
    );
  }
  if (!context.mounted) return;
  await openVideoSurface(context, (_) => _DeviceVideo.remote(
    streamUrl: streamUrl, title: title,
  ));
}

/// Opens app-private MP4 only while its owner-bound offline lease is valid.
Future<void> openDownloadedBreezzeVideo(
  BuildContext context, {
  required String filePath,
  required String title,
  required DateTime rightsExpiresAtUtc,
}) async {
  if (!supportsDeviceVideo || kIsWeb) {
    throw UnsupportedError('Offline file video is not available on this platform');
  }
  if (!rightsExpiresAtUtc.toUtc().isAfter(DateTime.now().toUtc())) {
    throw StateError('VIDEO_OFFLINE_LEASE_EXPIRED');
  }
  if (!await File(filePath).exists()) throw StateError('VIDEO_FILE_NOT_FOUND');
  if (!context.mounted) return;
  await openVideoSurface(context, (_) => _DeviceVideo.local(
    filePath: filePath, title: title,
  ));
}

class _DeviceVideo extends StatefulWidget {
  final XFile? file;
  final Uri? streamUrl;
  final String? filePath;
  final String? title;

  const _DeviceVideo({required this.file})
      : streamUrl = null, filePath = null, title = null;
  const _DeviceVideo.remote({required this.streamUrl, required this.title})
      : file = null, filePath = null;
  const _DeviceVideo.local({required this.filePath, required this.title})
      : file = null, streamUrl = null;

  @override
  State<_DeviceVideo> createState() => _DeviceVideoState();
}

class _DeviceVideoState extends State<_DeviceVideo> with WidgetsBindingObserver {
  late final VideoPlayerController _player;
  late final Future<void> _ready;
  // User opt-in only; never repeat protected media automatically by default.
  bool _repeat = false;
  bool _fillVideo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final path = widget.filePath ?? widget.file?.path ?? '';
    _player = widget.streamUrl != null
        ? VideoPlayerController.networkUrl(widget.streamUrl!)
        : kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(path))
            : path.startsWith('content://')
                ? VideoPlayerController.contentUri(Uri.parse(path))
                : VideoPlayerController.file(File(path));
    _ready = _player.initialize();
  }

  Future<void> _toggleRepeat() async {
    final next = !_repeat;
    try {
      await _player.setLooping(next);
      if (mounted) setState(() => _repeat = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change video repeat mode.')),
        );
      }
    }
  }

  Future<void> _seekBy(Duration delta) async {
    if (!_player.value.isInitialized) return;
    try {
      await _player.seekTo(videoSeekTarget(
        _player.value.position,
        delta,
        _player.value.duration,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not seek in this video.')),
        );
      }
    }
  }

  Future<void> _togglePlayback() async {
    try {
      final value = _player.value;
      if (value.isCompleted) {
        await _player.seekTo(Duration.zero);
        await _player.play();
      } else if (value.isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video playback is unavailable.')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: BzBrandedAppBar(
        title: widget.title ?? widget.file?.name ?? 'Video',
        leading: IconButton(
          tooltip: 'Back to music',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _ready,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('This video could not be played.'));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _player,
              builder: (context, value, _) {
                if (value.hasError) {
                  return const Center(child: Text('Video playback failed.'));
                }
                return Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bounds) {
                          final videoSize = value.size;
                          return ClipRect(
                            child: SizedBox(
                              width: bounds.maxWidth,
                              height: bounds.maxHeight,
                              child: FittedBox(
                                alignment: Alignment.center,
                                fit: _fillVideo ? BoxFit.cover : BoxFit.contain,
                                child: SizedBox(
                                  width: videoSize.width > 0 ? videoSize.width : 16,
                                  height: videoSize.height > 0 ? videoSize.height : 9,
                                  child: VideoPlayer(_player),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    VideoProgressIndicator(
                      _player,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: theme.colorScheme.onSurface,
                        bufferedColor: theme.colorScheme.onSurface.withValues(alpha: 0.28),
                        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Rewind 10 seconds',
                          icon: const BzSvgIcon(name: 'rewind', size: 26),
                          onPressed: () => _seekBy(const Duration(seconds: -10)),
                        ),
                        IconButton(
                          tooltip: value.isCompleted
                              ? 'Replay video'
                              : value.isPlaying ? 'Pause video' : 'Play video',
                          icon: BzSvgIcon(
                            name: value.isPlaying ? 'pause' : 'play',
                            color: theme.colorScheme.onSurface,
                            size: 28,
                          ),
                          onPressed: _togglePlayback,
                        ),
                        IconButton(
                          tooltip: 'Forward 10 seconds',
                          icon: const BzSvgIcon(name: 'fast-forward', size: 26),
                          onPressed: () => _seekBy(const Duration(seconds: 10)),
                        ),
                        Text(
                          '${videoClock(value.position)} / ${videoClock(value.duration)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        TextButton.icon(
                          onPressed: _toggleRepeat,
                          icon: const BzSvgIcon(name: 'repeat', size: 20),
                          label: Text(_repeat ? 'Repeat on' : 'Repeat off'),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _fillVideo = !_fillVideo),
                          icon: const BzSvgIcon(name: 'video', size: 20),
                          label: Text(_fillVideo ? 'Fit video' : 'Fill screen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
