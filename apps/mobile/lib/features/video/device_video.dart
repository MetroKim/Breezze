import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'open_youtube_player.dart';

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

/// Plays only an authorized, backend-signed R2 MP4, never a raw YouTube URL.
Future<void> openAuthorizedBreezzeVideo(
  BuildContext context, {
  required Uri streamUrl,
  required String title,
}) async {
  final segments = streamUrl.pathSegments;
  if (streamUrl.scheme != 'https' || segments.length != 3 ||
      segments.first != 'video' || segments.last != 'stream' ||
      !RegExp(r'^[0-9a-fA-F-]{36}
  final XFile file;
  const _DeviceVideo({required this.file});

  @override
  State<_DeviceVideo> createState() => _DeviceVideoState();
}

class _DeviceVideoState extends State<_DeviceVideo> with WidgetsBindingObserver {
  late final VideoPlayerController _player;
  late final Future<void> _ready;
  bool _closing = false;

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

  void _onFrame() {
    if (!_closing && mounted && _player.value.isCompleted && ModalRoute.of(context)?.isCurrent == true) {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title ?? widget.file?.name ?? 'Video')),
    body: Center(child: FutureBuilder<void>(future: _ready, builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('This video could not be played.');
      if (snapshot.connectionState != ConnectionState.done) return const CircularProgressIndicator();
      return ValueListenableBuilder<VideoPlayerValue>(valueListenable: _player, builder: (context, value, _) {
        if (value.hasError) return const Text('Video playback failed.');
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(_player))),
          VideoProgressIndicator(_player, allowScrubbing: true),
          IconButton(tooltip: value.isPlaying ? 'Pause video' : 'Play video',
            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: value.isPlaying ? _player.pause : _player.play),
        ]);
      });
    })),
  );
}
).hasMatch(segments[1]) ||
      streamUrl.queryParameters['e'] == null ||
      streamUrl.queryParameters['s'] == null) {
    throw ArgumentError.value(streamUrl, 'streamUrl', 'invalid licensed video source');
  }
  if (!context.mounted) return;
  await openVideoSurface(context, (_) => _DeviceVideo.remote(
    streamUrl: streamUrl, title: title,
  ));
}

/// Opens an app-private MP4 only while its owner-bound offline lease is valid.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final path = widget.file.path;
    _player = kIsWeb ? VideoPlayerController.networkUrl(Uri.parse(path))
        : path.startsWith('content://') ? VideoPlayerController.contentUri(Uri.parse(path))
        : VideoPlayerController.file(File(path));
    _ready = _player.initialize();
    _player.addListener(_onFrame);
  }

  void _onFrame() {
    if (!_closing && mounted && _player.value.isCompleted && ModalRoute.of(context)?.isCurrent == true) {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.file.name)),
    body: Center(child: FutureBuilder<void>(future: _ready, builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('This video could not be played.');
      if (snapshot.connectionState != ConnectionState.done) return const CircularProgressIndicator();
      return ValueListenableBuilder<VideoPlayerValue>(valueListenable: _player, builder: (context, value, _) {
        if (value.hasError) return const Text('Video playback failed.');
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(_player))),
          VideoProgressIndicator(_player, allowScrubbing: true),
          IconButton(tooltip: value.isPlaying ? 'Pause video' : 'Play video',
            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: value.isPlaying ? _player.pause : _player.play),
        ]);
      });
    })),
  );
}
