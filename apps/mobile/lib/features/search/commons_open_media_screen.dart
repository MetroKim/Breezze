import 'dart:io';

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio/commons_device_download.dart';
import '../../core/auth/auth_session.dart';
import '../player/player_controller.dart';

/// An explicitly labeled online source, separate from Spotify/Deezer metadata
/// and official YouTube video discovery. Streaming and downloads require a
/// fresh backend /resolve (not a bare link taken from search results).
class CommonsOpenMediaScreen extends ConsumerStatefulWidget {
  const CommonsOpenMediaScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<CommonsOpenMediaScreen> createState() =>
      _CommonsOpenMediaScreenState();
}

class _CommonsOpenMediaScreenState extends ConsumerState<CommonsOpenMediaScreen> {
  late final TextEditingController _query;
  String _kind = 'audio';
  List<CommonsDeviceMedia> _items = [];
  bool _loading = false;
  String? _error;
  String? _busy;
  final Map<String, String> _downloadedPaths = {};
  List<CommonsSavedMedia> _saved = [];
  bool _showSaved = false;
  int _generation = 0;
  int _savedGeneration = 0;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSaved());
    if (widget.initialQuery.trim().length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _generation++;
    _savedGeneration++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _restoreSaved() async {
    final auth = ref.read(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : null;
    final generation = ++_savedGeneration;
    if (ownerId == null) {
      if (mounted) setState(() => _saved = []);
      return;
    }
    try {
      final saved = await CommonsDeviceDownload().listSaved(ownerId: ownerId);
      if (!mounted || generation != _savedGeneration) return;
      final current = ref.read(authSessionProvider);
      if (current is! AuthSignedIn || current.userId != ownerId) return;
      setState(() => _saved = saved);
    } catch (_) {
      if (mounted && generation == _savedGeneration) {
        setState(() => _saved = []);
      }
    }
  }

  Future<void> _playSaved(CommonsSavedMedia item) async {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || !_saved.any((m) => m.file.path == item.file.path)) {
      return;
    }
    if (!await item.file.exists()) {
      await _restoreSaved();
      return;
    }
    if (item.kind == 'audio') {
      final key = sha256.convert(utf8.encode(item.fileTitle)).toString();
      await ref.read(playerControllerProvider.notifier).playTrack(
        trackId: 'commons:$key',
        title: item.title,
        artist: item.creator ?? 'Wikimedia Commons',
        localFilePath: item.file.path,
        origin: 'open-media-downloads',
        sourceContext: 'Downloaded open media',
      );
    } else {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CommonsVideoPlayerScreen(
          source: item.file.uri, title: item.title,
          sourcePage: item.sourcePage, license: item.license,
        ),
      ));
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });
    try {
      final api = ref.read(authSessionProvider.notifier).api;
      final result = await api.searchOpenMedia(query: query, kind: _kind);
      if (!mounted || generation != _generation) return;
      if (result['enabled'] != true) {
        setState(() {
          _items = [];
          _error = 'Online open-media provider is not enabled on this server.';
        });
      } else {
        final raw = result['items'];
        final items = <CommonsDeviceMedia>[];
        if (raw is List) {
          for (final candidate in raw) {
            if (candidate is Map<String, dynamic>) {
              try {
                items.add(CommonsDeviceMedia.fromJson(candidate));
              } on FormatException {
                // Invalid rights/host metadata never becomes a playable result.
              }
            }
          }
        }
        setState(() => _items = items);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Online source unavailable. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<CommonsDeviceMedia> _fresh(CommonsDeviceMedia item) async {
    final api = ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) {
      throw StateError('Sign in to access online media.');
    }
    final raw = await api.resolveOpenMedia(
      fileTitle: item.fileTitle, kind: item.kind,
    );
    final resolved = CommonsDeviceMedia.fromJson(raw);
    if (resolved.fileTitle != item.fileTitle ||
        resolved.kind != item.kind) {
      throw const FormatException('OPEN_MEDIA_FILE_CHANGED');
    }
    return resolved;
  }

  Future<void> _play(CommonsDeviceMedia item) async {
    if (_busy != null) return;
    setState(() => _busy = item.fileTitle);
    try {
      final resolved = await _fresh(item);
      if (!mounted) return;
      if (resolved.kind == 'audio') {
        final id = sha256.convert(utf8.encode(resolved.fileTitle)).toString();
        await ref.read(playerControllerProvider.notifier).playTrack(
          trackId: 'commons:$id',
          title: resolved.title,
          artist: resolved.creator ?? 'Wikimedia Commons',
          approvedOnlineUrl: resolved.streamUrl,
          origin: 'commons',
          sourceContext: 'Open media',
        );
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CommonsVideoPlayerScreen(
            source: Uri.parse(resolved.streamUrl),
            title: resolved.title,
            sourcePage: resolved.sourceUrl,
            license: resolved.license,
          ),
        ));
      }
    } catch (_) {
      if (mounted) _message('This recording cannot currently be played.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _download(CommonsDeviceMedia item) async {
    if (_busy != null) return;
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) {
      _message('Sign in to download this recording.');
      return;
    }
    setState(() => _busy = item.fileTitle);
    try {
      final resolved = await _fresh(item);
      final saved = await CommonsDeviceDownload().save(
        media: resolved, ownerId: auth.userId,
        stillAuthorizedOwner: () {
          final latest = ref.read(authSessionProvider);
          return latest is AuthSignedIn && latest.userId == auth.userId;
        },
      );
      if (!mounted) return;
      final current = ref.read(authSessionProvider);
      if (current is! AuthSignedIn || current.userId != auth.userId) {
        // Account switching must not display another user's saved file.
        return;
      }
      setState(() => _downloadedPaths[item.fileTitle] = saved.path);
      await _restoreSaved();
      _message('Saved on this device. License and source details retained.');
    } catch (_) {
      if (mounted) _message('Download failed or source permission changed.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      final before = previous is AuthSignedIn ? previous.userId : null;
      final after = next is AuthSignedIn ? next.userId : null;
      if (before != after) {
        _generation++;
        _savedGeneration++;
        setState(() {
          _items = [];
          _saved = [];
          _downloadedPaths.clear();
          _loading = false;
        });
        _restoreSaved();
      }
    });
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Open media')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Creative Commons audio and video. Not the Spotify or YouTube commercial catalog.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _query,
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search online audio or video',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: _search,
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: 'Search online media',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.download_done_outlined),
                    label: Text('Saved on device (${_saved.length})'),
                    onPressed: () => setState(() => _showSaved = !_showSaved),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('Audio'),
                        selected: _kind == 'audio',
                        onSelected: (_) {
                          setState(() => _kind = 'audio');
                          _search();
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Video'),
                        selected: _kind == 'video',
                        onSelected: (_) {
                          setState(() => _kind = 'video');
                          _search();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _showSaved
                ? (_saved.isEmpty
                    ? const Center(child: Text('No open-media files saved on this device.'))
                    : ListView.builder(
                        itemCount: _saved.length,
                        itemBuilder: (context, i) {
                          final item = _saved[i];
                          return ListTile(
                            leading: Icon(item.kind == 'audio'
                                ? Icons.music_note : Icons.movie_outlined),
                            title: Text(item.title),
                            subtitle: Text('${item.license} · saved on this device'),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Play downloaded file offline',
                              onPressed: () => _playSaved(item),
                            ),
                          );
                        },
                      ))
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                    ? const Center(child: Text(
                        'Search to discover downloadable open audio and video.',
                      ))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          final busy = _busy == item.fileTitle;
                          return ListTile(
                            title: Text(item.title, maxLines: 2),
                            subtitle: Text(
                              '${item.license} · ${item.creator ?? "Source: Wikimedia Commons"}\n'
                              'Attribution and source retained with downloads.',
                              maxLines: 3,
                              style: theme.textTheme.bodySmall,
                            ),
                            isThreeLine: true,
                            leading: Icon(item.kind == 'audio'
                              ? Icons.music_note : Icons.movie_outlined),
                            trailing: Wrap(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Play online',
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: _busy == null ? () => _play(item) : null,
                                ),
                                IconButton(
                                  tooltip: 'Download to device',
                                  icon: busy
                                    ? const Icon(Icons.hourglass_top)
                                    : Icon(_downloadedPaths.containsKey(item.fileTitle)
                                      ? Icons.check : Icons.download),
                                  onPressed: _busy == null ? () => _download(item) : null,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Native video playback is separate from the one global audio player.
/// Device support varies for the open WebM/Ogg formats hosted by Commons.
class CommonsVideoPlayerScreen extends StatefulWidget {
  const CommonsVideoPlayerScreen({
    super.key,
    required this.source,
    required this.title,
    required this.sourcePage,
    required this.license,
  });

  final Uri source;
  final String title;
  final String sourcePage;
  final String license;

  @override
  State<CommonsVideoPlayerScreen> createState() =>
      _CommonsVideoPlayerScreenState();
}

class _CommonsVideoPlayerScreenState extends State<CommonsVideoPlayerScreen> {
  VideoPlayerController? _video;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final player = widget.source.scheme == 'file'
          ? VideoPlayerController.file(File.fromUri(widget.source))
          : VideoPlayerController.networkUrl(widget.source);
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() => _video = player);
      await player.play();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'This device cannot play the selected video format.');
      }
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _video;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (player == null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error ?? 'Loading video...'),
              )
            else
              AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            if (player != null)
              IconButton(
                tooltip: player.value.isPlaying ? 'Pause' : 'Play',
                icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (player.value.isPlaying) {
                    player.pause();
                  } else {
                    player.play();
                  }
                  setState(() {});
                },
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText('${widget.license} · ${widget.sourcePage}'),
            ),
          ],
        ),
      ),
    );
  }
}
