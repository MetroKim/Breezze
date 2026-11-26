import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'open_youtube_player.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_branded_app_bar.dart';

bool get supportsDeviceVideo => kIsWeb ||
    [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS].contains(defaultTargetPlatform);

Future<void> pickDeviceVideo(BuildContext context) async {
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
  final segments = streamUrl.pathSegments;
  if (streamUrl.scheme != 'https' || segments.length != 3 ||
      segments.first != 'video' || segments.last != 'stream' ||
      !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(segments[1]) ||
      streamUrl.queryParameters['e'] == null ||
      streamUrl.queryParameters['s'] == null) {
    throw ArgumentError.value(streamUrl, 'streamUrl', 'invalid licensed video source');
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
  bool _closing = false;
  // User opt-in only; never repeat protected media automatically by default.
  bool _repeat = false;

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
    _player.addListener(_onFrame);
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

  void _onFrame() {
    if (!_repeat && !_closing && mounted && _player.value.isCompleted &&
        ModalRoute.of(context)?.isCurrent == true) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_onFrame);
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
                      child: ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: value.aspectRatio > 0
                                ? value.aspectRatio : 16 / 9,
                            child: VideoPlayer(_player),
                          ),
                        ),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                          icon: BzSvgIcon(
                            name: value.isPlaying ? 'pause' : 'play',
                            color: theme.colorScheme.onSurface,
                            size: 28,
                          ),
                          onPressed: value.isPlaying ? _player.pause : _player.play,
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          onPressed: _toggleRepeat,
                          icon: const BzSvgIcon(name: 'repeat', size: 20),
                          label: Text(_repeat ? 'Repeat on' : 'Repeat off'),
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
