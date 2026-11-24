import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../app/downloads_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../widgets/bz_brand_icons.dart';
import '../player/player_controller.dart';
import '../video/device_video.dart';

/// Downloads library — offline tracks with cover art + lyrics, plus a
/// live in-progress section (§6.1).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  List<DownloadedTrack> _tracks = [];
  List<DownloadedVideo> _videos = [];
  int _storageBytes = 0;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) {
      if (!mounted) return;
      setState(() {
        _tracks = [];
        _videos = [];
        _loading = false;
      });
      return;
    }
    final dir = await downloadsDirectory(userId: auth.userId);
    final library = DownloadsLibrary(
      root: dir,
      lyrics: ref.read(lyricsProvider),
    );
    var tracks = await library.list(ownerId: auth.userId);

    // Whenever the account is online, ask the backend to re-check takedowns,
    // territory and current download rights before extending each local lease.
    final api = ref.read(authSessionProvider.notifier).api;
    if (api.accessToken != null) {
      for (final track in tracks) {
        try {
          final lease = await api.revalidateOfflineLease(
            trackId: track.catalogTrackId,
            territory: ref.read(outboxTerritoryProvider),
          );
          if (lease['allowed'] != true) {
            await library.remove(track.trackId);
            continue;
          }
          final rawExpiry = lease['offlineLeaseExpiresAt'] as String?;
          final expiry = rawExpiry == null ? null : DateTime.tryParse(rawExpiry);
          if (rawExpiry != null && expiry == null) continue;
          await library.updateOfflineLease(track.trackId, expiry);
        } catch (_) {
          // A transient network failure does not erase a still-valid offline lease.
        }
      }
      tracks = await library.list(ownerId: auth.userId);
    }
    var videos = await library.listVideos(ownerId: auth.userId);
    if (api.accessToken != null) {
      for (final video in videos) {
        try {
          final lease = await api.revalidateVideoDownload(video.videoAssetId);
          if (lease['allowed'] != true) {
            await library.removeVideo(video.videoAssetId);
            ref.read(downloadProgressProvider.notifier).forgetVideo(video.videoAssetId);
            continue;
          }
          final expiry = DateTime.tryParse(lease['offlineLeaseExpiresAt'] as String? ?? '')?.toUtc();
          if (expiry != null) {
            await library.updateVideoOfflineLease(video.videoAssetId, expiry);
          }
        } catch (_) {
          // Network failures cannot invalidate a still-valid offline lease.
        }
      }
      videos = await library.listVideos(ownerId: auth.userId);
    }
    var storageBytes = 0;
    for (final track in tracks) {
      for (final filePath in [track.audioPath, track.coverPath, track.lyricsPath]) {
        if (filePath == null) continue;
        try {
          final file = File(filePath);
          if (await file.exists()) storageBytes += await file.length();
        } catch (_) {
          // A file can disappear while the OS is reclaiming storage.
        }
      }
    }
    for (final video in videos) {
      try { storageBytes += await File(video.filePath).length(); } catch (_) {}
    }
    if (!mounted) return;
    final latestAuth = ref.read(authSessionProvider);
    if (latestAuth is! AuthSignedIn || latestAuth.userId != auth.userId) {
      setState(() {
        _tracks = [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _tracks = tracks;
      _storageBytes = storageBytes;
      _loading = false;
    });
  }

  void _play(DownloadedTrack track) {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || auth.userId != track.ownerId) return;
    final expiry = track.rightsExpiresAtUtc;
    if (expiry != null && !expiry.isAfter(DateTime.now().toUtc())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This download has expired. Connect to the internet and download it again.'),
        ),
      );
      return;
    }
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.catalogTrackId,
          title: track.title,
          artist: track.artist,
          localFilePath: track.audioPath,
          origin: 'downloads',
          sourceContext: 'Downloads',
        );
  }

  Future<void> _playVideo(DownloadedVideo video) async {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || auth.userId != video.ownerId) return;
    if (!video.rightsExpiresAtUtc.isAfter(DateTime.now().toUtc())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This video download has expired. Reconnect to renew its license.')),
      );
      return;
    }
    try {
      await openDownloadedBreezzeVideo(
        context,
        filePath: video.filePath,
        title: video.title,
        rightsExpiresAtUtc: video.rightsExpiresAtUtc,
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This offline video could not be opened.')),
      );
    }
  }

  Future<void> _removeVideo(DownloadedVideo video) async {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || auth.userId != video.ownerId) return;
    final dir = await downloadsDirectory(userId: auth.userId);
    await DownloadsLibrary(root: dir, lyrics: ref.read(lyricsProvider))
        .removeVideo(video.videoAssetId);
    ref.read(downloadProgressProvider.notifier).forgetVideo(video.videoAssetId);
    try {
      await ref.read(authSessionProvider.notifier).api
          .removeVideoDownload(video.videoAssetId);
    } catch (_) {
      // Local deletion works even without network access.
    }
    await _refresh();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _freeUpSpace() async {
    if (_tracks.isEmpty && _videos.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: Text(
          'This removes ${_tracks.length} audio tracks and ${_videos.length} videos '
          'and frees approximately ${_formatBytes(_storageBytes)} on this device. '
          'Your playlists and library will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove downloads'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return;
    final dir = await downloadsDirectory(userId: auth.userId);
    final library = DownloadsLibrary(root: dir, lyrics: ref.read(lyricsProvider));
    for (final track in List<DownloadedTrack>.of(_tracks)) {
      if (track.ownerId == auth.userId) await library.remove(track.trackId);
    }
    for (final video in List<DownloadedVideo>.of(_videos)) {
      if (video.ownerId != auth.userId) continue;
      await library.removeVideo(video.videoAssetId);
      ref.read(downloadProgressProvider.notifier).forgetVideo(video.videoAssetId);
      try {
        await ref.read(authSessionProvider.notifier).api
            .removeVideoDownload(video.videoAssetId);
      } catch (_) {}
    }
    await _refresh();
  }

  Future<void> _remove(DownloadedTrack track) async {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || auth.userId != track.ownerId) return;
    final dir = await downloadsDirectory(userId: auth.userId);
    await DownloadsLibrary(
      root: dir,
      lyrics: ref.read(lyricsProvider),
    ).remove(track.trackId);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      _refresh();
    });
    final theme = Theme.of(context);
    final progress = ref.watch(downloadProgressProvider);
    final jobStatuses = ref.watch(downloadJobStatusProvider);
    final downloadController = ref.read(downloadProgressProvider.notifier);
    final inProgress = jobStatuses.entries.where((entry) => ['downloading', 'paused', 'failed', 'waiting_for_wifi', 'waiting_for_network'].contains(entry.value)).map((entry) => MapEntry(entry.key, progress[entry.key] ?? 0.0)).toList();

    // Refresh the completed list when the last in-flight download ends.
    if (inProgress.isEmpty && (_tracks.isNotEmpty || _videos.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfNeeded());
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Downloads',
                      style: theme.textTheme.displayMedium),
                ),
                IconButton(
                  icon: BzSvgIcon(name: 'refresh'),
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.bzSurface1,
                  borderRadius: BorderRadius.circular(BzRadius.card),
                  border: Border.all(color: theme.bzSeparator),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DEVICE STORAGE', style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.bzText2, letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                          )),
                          const SizedBox(height: 4),
                          Text(_formatBytes(_storageBytes), style: theme.textTheme.titleLarge),
                          Text('${_tracks.length} audio tracks · ${_videos.length} videos',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _tracks.isEmpty && _videos.isEmpty ? null : _freeUpSpace,
                      child: const Text('Free Up Space'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, __) => const BzSkeletonTrackRow(),
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(0, 8, 0, BzBreakpoints.bottomClearance(context, compact: 220)),
                    children: [
                      // In-progress section (live)
                      for (final entry in inProgress)
                        ListTile(
                          leading: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                          ),
                          title: Text(
                              jobStatuses[entry.key] == 'failed' ? 'Download failed' : jobStatuses[entry.key] == 'waiting_for_wifi' ? 'Waiting for Wi-Fi' : jobStatuses[entry.key] == 'waiting_for_network' ? 'Waiting for network' : jobStatuses[entry.key] == 'paused' ? 'Paused · ${(entry.value * 100).round()}%' : 'Downloading… ${(entry.value * 100).round()}%',
                              style: theme.textTheme.titleMedium),
                          subtitle: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: entry.value,
                              minHeight: 3,
                              backgroundColor: theme.bzSeparator,
                              color: theme.bzAccent,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () {
                                  if (['failed', 'waiting_for_wifi', 'waiting_for_network'].contains(jobStatuses[entry.key])) {
                                    downloadController.retry(entry.key);
                                  } else if (jobStatuses[entry.key] == 'paused') {
                                    downloadController.resume(entry.key);
                                  } else {
                                    downloadController.pause(entry.key);
                                  }
                                },
                                child: Text(['failed', 'waiting_for_wifi', 'waiting_for_network'].contains(jobStatuses[entry.key]) ? 'Retry' : jobStatuses[entry.key] == 'paused' ? 'Resume' : 'Pause'),
                              ),
                              IconButton(
                                tooltip: 'Cancel download',
                                onPressed: () => downloadController.cancel(entry.key),
                                icon: const BzSvgIcon(name: 'close'),
                              ),
                            ],
                          ),
                        ),
                      // Completed downloads
                      if (_tracks.isEmpty && _videos.isEmpty && inProgress.isEmpty)
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 48),
                              BzBnoteMark(size: 64, color: theme.bzText2),
                              const SizedBox(height: 16),
                              Text('No downloads yet',
                                  style: theme.textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Text(
                                  'Search a song and tap the download icon.',
                                  style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        )
                      else
                        for (final track in _tracks)
                          ListTile(
                            leading: track.coverPath != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                        BzRadius.artwork),
                                    child: Image.file(
                                      File(track.coverPath!),
                                      width: 48,
                                      height: 48,
                                      errorBuilder: (_, __, ___) =>
                                          BzBnoteMark(
                                              size: 48, color: theme.bzText2),
                                    ),
                                  )
                                : BzBnoteMark(size: 48, color: theme.bzText2),
                            title: Text(track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${track.artist}'
                              '${track.lyricsPath != null ? ' · lyrics saved' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: BzSvgIcon(name: 'trash'),
                                  onPressed: () => _remove(track),
                                ),
                                BzSvgIcon(name: 'download-done',
                                    color: Colors.green),
                              ],
                            ),
                            onTap: () => _play(track),
                          ),
                       for (final video in _videos)
                         ListTile(
                           leading: const BzSvgIcon(name: 'video', size: 42),
                           title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                           subtitle: Text(
                             video.rightsExpiresAtUtc.isAfter(DateTime.now().toUtc())
                                 ? 'Offline MP4 · Licensed Breezze video'
                                 : 'Video license expired',
                           ),
                           trailing: IconButton(
                             tooltip: 'Remove offline video',
                             icon: const BzSvgIcon(name: 'trash'),
                             onPressed: () => _removeVideo(video),
                           ),
                           onTap: () => _playVideo(video),
                         ),

                    ],
                  ),
          ),
        ],
      ),
    );
  }

  var _refreshedAt = 0;

  void _refreshIfNeeded() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _refreshedAt < 1000) return; // throttle
    _refreshedAt = now;
    _refresh();
  }
}
