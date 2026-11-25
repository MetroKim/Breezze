import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/api/breezze_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/auth/auth_session.dart';
import '../core/audio/authorized_download_grant.dart';
import '../core/database/database_providers.dart';
import '../core/database/outbox_sync_service.dart';
import 'bootstrap.dart';
import 'download_preferences.dart';

/// User-facing status for a deliberately denied offline grant. The app does
/// not retry missing masters or absent licensing as if they were Wi-Fi errors.
String downloadDenialStatus(Object? reason) => switch (reason) {
  'LICENSED_AUDIO_NOT_INGESTED' ||
  'LICENSED_AUDIO_FORMAT_INVALID' => 'media_unavailable',
  'DOWNLOAD_RENDITION_UNSUPPORTED' => 'format_unavailable',
  'PROVIDER_DOWNLOAD_UNSUPPORTED' ||
  'NO_EXPLICIT_AUTHORIZATION' ||
  'PREVIEW_ONLY' ||
  'NOT_AVAILABLE_IN_TERRITORY' ||
  'RIGHTS_WINDOW_NOT_OPEN' ||
  'RIGHTS_EXPIRED' ||
  'TAKEDOWN_ACTIVE' => 'not_licensed',
  _ => 'failed',
};

/// Owner-specific queue filename. The legacy global jobs.json did not carry
/// an owner ID and must never be silently imported by a different listener.
String scopedDownloadJobsFilename(String userId) {
  if (userId.trim().isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'owner required');
  }
  return '${base64Url.encode(utf8.encode(userId)).replaceAll('=', '')}.json';
}

/// Live transfer progress and queue state, keyed by track ID.
final downloadJobStatusProvider = StateProvider<Map<String, String>>((ref) => {});

/// Live download progress, keyed by track id: 0.0–1.0, removed on finish.
final downloadProgressProvider =
    StateNotifierProvider<DownloadsController, Map<String, double>>(
        DownloadsController.new);

/// Downloads only short-lived URLs authorized by the Breezze backend.
/// Provider metadata/search adapters are never allowed to grant download
/// rights or expose a raw stream URL.
class DownloadsController extends StateNotifier<Map<String, double>> {
  DownloadsController(this.ref) : super({}) {
    ref.listen<AuthState>(authSessionProvider, (_, next) {
      _switchOwner(next is AuthSignedIn ? next.userId : null);
    });
    final initial = ref.read(authSessionProvider);
    _switchOwner(initial is AuthSignedIn ? initial.userId : null);
  }

  final Ref ref;
  String? _ownerId;

  void _switchOwner(String? nextOwner) {
    if (_ownerId == nextOwner) return;
    for (final pending in _cancellations.values) {
      pending.cancel();
    }
    _cancellations.clear();
    _tracks.clear();
    _videoTitles.clear();
    _ownerId = nextOwner;
    if (!mounted) return;
    state = {};
    ref.read(downloadJobStatusProvider.notifier).state = {};
    if (nextOwner != null) unawaited(_restoreJobs(nextOwner));
  }
  final Map<String, DownloadCancellation> _cancellations = {};
  final Map<String, BzTrack> _tracks = {};
  final Map<String, String> _videoTitles = {};

  Future<File> _jobsFile(String ownerId) async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}/Breezze/Downloads/Jobs');
    await folder.create(recursive: true);
    return File('${folder.path}/${scopedDownloadJobsFilename(ownerId)}');
  }

  Future<void> _persistJobs() async {
    final ownerId = _ownerId;
    if (ownerId == null || !mounted) return;
    try {
      final records = <String, Object?>{};
      final statuses = ref.read(downloadJobStatusProvider);
      for (final entry in _tracks.entries) {
        final track = entry.value;
        records[entry.key] = {
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'artworkUrl': track.artworkUrl,
          'durationMs': track.duration.inMilliseconds,
          'explicit': track.explicit,
          'status': statuses[entry.key] ?? 'queued',
        };
      }
      for (final entry in _videoTitles.entries) {
        final key = 'video:${entry.key}';
        records[key] = {
          'kind': 'video',
          // Jobs file is shared at the app level; do not expose video titles
          // belonging to a different signed-in listener.
          'title': 'Video',
          'status': statuses[key] ?? 'queued',
        };
      }
      final file = await _jobsFile(ownerId);
      if (!mounted || _ownerId != ownerId) return;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(records), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {}
  }

  Future<void> _restoreJobs(String ownerId) async {
    try {
      final file = await _jobsFile(ownerId);
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final statuses = <String, String>{};
      final tracks = <String, BzTrack>{};
      final videos = <String, String>{};
      for (final entry in decoded.entries) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final saved = item['status'] as String? ?? 'failed';
        // The library independently verifies completed audio files and leases.
        // A stale JSON job cannot declare that music is downloaded.
        if (saved == 'downloaded' || saved == 'cancelled') continue;
        final status = saved == 'downloading' ? 'paused' : saved;
        if (item['kind'] == 'video' && entry.key.startsWith('video:')) {
          final id = entry.key.substring('video:'.length);
          if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
            videos[id] = 'Video';
            statuses[entry.key] = status;
          }
          continue;
        }
        tracks[entry.key] = BzTrack(
          id: entry.key,
          title: item['title'] as String? ?? 'Unknown track',
          artist: item['artist'] as String? ?? 'Unknown artist',
          album: item['album'] as String?,
          artworkUrl: item['artworkUrl'] as String?,
          duration: Duration(
            milliseconds: (item['durationMs'] as num?)?.toInt() ?? 0,
          ),
          explicit: item['explicit'] == true,
        );
        statuses[entry.key] = status;
      }
      // Discard async restore results if this session is no longer the owner.
      if (!mounted || _ownerId != ownerId) return;
      for (final item in tracks.entries) {
        _tracks.putIfAbsent(item.key, () => item.value);
      }
      for (final item in videos.entries) {
        _videoTitles.putIfAbsent(item.key, () => item.value);
      }
      // Prefer freshly created jobs over any stale persisted snapshot.
      ref.read(downloadJobStatusProvider.notifier).state = {
        ...statuses,
        ...ref.read(downloadJobStatusProvider),
      };
    } catch (_) {
      // A bad jobs.json cannot authorize or expose any audio.
    }
  }

  void _setStatus(String id, String status) {
    if (!mounted || _ownerId == null) return;
    final next = Map<String, String>.of(ref.read(downloadJobStatusProvider));
    next[id] = status;
    ref.read(downloadJobStatusProvider.notifier).state = next;
    _persistJobs();
  }

  void forgetVideo(String videoAssetId) {
    final key = 'video:$videoAssetId';
    _cancellations.remove(key)?.cancel();
    _videoTitles.remove(videoAssetId);
    if (mounted) {
      final next = Map<String, String>.of(ref.read(downloadJobStatusProvider))
        ..remove(key);
      ref.read(downloadJobStatusProvider.notifier).state = next;
      state = Map<String, double>.of(state)..remove(key);
    }
    _persistJobs();
  }

  Future<void> pause(String trackId) async {
    _setStatus(trackId, 'paused');
    _cancellations[trackId]?.cancel();
  }

  Future<void> resume(String trackId) async {
    if (trackId.startsWith('video:')) {
      final assetId = trackId.substring('video:'.length);
      final title = _videoTitles[assetId];
      if (title != null) await downloadVideo(videoAssetId: assetId, title: title);
      return;
    }
    final track = _tracks[trackId];
    if (track != null) {
      final next = Map<String, double>.of(state)..remove(trackId);
      state = next;
      await download(track);
    }
  }

  Future<void> retry(String trackId) async {
    if (trackId.startsWith('video:')) {
      final assetId = trackId.substring('video:'.length);
      final title = _videoTitles[assetId];
      if (title != null) await downloadVideo(videoAssetId: assetId, title: title);
      return;
    }
    final track = _tracks[trackId];
    if (track != null) await download(track);
  }

  Future<void> cancel(String trackId) async {
    _setStatus(trackId, 'cancelled');
    _cancellations[trackId]?.cancel();
    if (trackId.startsWith('video:')) {
      final auth = ref.read(authSessionProvider);
      if (auth is AuthSignedIn) {
        final dir = await downloadsDirectory(userId: auth.userId);
        final library = DownloadsLibrary(root: dir, lyrics: ref.read(lyricsProvider));
        await library.removeVideoPartial(trackId.substring('video:'.length));
      }
      if (mounted) state = Map<String, double>.of(state)..remove(trackId);
      return;
    }
    final auth = ref.read(authSessionProvider);
    if (auth is AuthSignedIn) {
      final dir = await downloadsDirectory(userId: auth.userId);
      await DownloadsLibrary(root: dir, lyrics: ref.read(lyricsProvider)).removePartial(trackId);
    }
    if (mounted) {
      final next = Map<String, double>.of(state)..remove(trackId);
      state = next;
    }
  }

  /// Licensed MP4 jobs share the existing download queue and transfer library.
  Future<void> downloadVideo({
    required String videoAssetId,
    required String title,
  }) async {
    if (_ownerId == null) return;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(videoAssetId)) return;
    final key = 'video:$videoAssetId';
    final ownerId = _ownerId;
    if (ownerId == null) return;
    if (state.containsKey(key) ||
        ref.read(downloadJobStatusProvider)[key] == 'downloaded') return;
    _videoTitles[videoAssetId] = title;
    final cancellation = DownloadCancellation();
    _cancellations[key] = cancellation;
    _setStatus(key, 'downloading');
    try {
      final preferences = await DownloadPreferencesStore().load();
      final network = await Connectivity().checkConnectivity();
      final onWifi = network.contains(ConnectivityResult.wifi);
      final onMobile = network.contains(ConnectivityResult.mobile);
      if (!onWifi && (!onMobile || preferences.wifiOnly || !preferences.allowCellular)) {
        _setStatus(key, onMobile ? 'waiting_for_wifi' : 'waiting_for_network');
        return;
      }
      final auth = ref.read(authSessionProvider);
      if (auth is! AuthSignedIn || auth.userId != ownerId ||
          cancellation.isCancelled) {
        return;
      }
      final api = ref.read(authSessionProvider.notifier).api;
      if (api.accessToken == null) { _setStatus(key, 'failed'); return; }
      final result = await api.authorizeVideoDownload(videoAssetId);
      if (cancellation.isCancelled) return;
      if (result['allowed'] != true || result['videoAssetId'] != videoAssetId ||
          result['mimeType'] != 'video/mp4') {
        _setStatus(key, 'failed');
        return;
      }
      final url = result['url'] as String?;
      final leaseRaw = result['offlineLeaseExpiresAt'] as String?;
      final lease = DateTime.tryParse(leaseRaw ?? '')?.toUtc();
      final uri = url == null ? null : Uri.tryParse(url);
      if (url == null || uri == null || uri.scheme != 'https' || uri.pathSegments.length != 3 ||
          uri.pathSegments.first != 'video' ||
          uri.pathSegments[1] != videoAssetId ||
          uri.pathSegments.last != 'download' ||
          lease == null || !lease.isAfter(DateTime.now().toUtc())) {
        _setStatus(key, 'failed');
        return;
      }
      state = {...state, key: 0.0};
      final dir = await downloadsDirectory(userId: auth.userId);
      final library = DownloadsLibrary(root: dir, lyrics: ref.read(lyricsProvider));
      final ok = await library.downloadVideo(
        videoAssetId: videoAssetId,
        title: title,
        ownerId: auth.userId,
        downloadUrl: url,
        rightsExpiresAtUtc: lease,
        cancellation: cancellation,
        onProgress: (value) {
          if (mounted && !cancellation.isCancelled && _ownerId == ownerId) {
            state = {...state, key: value};
          }
        },
      );
      if (cancellation.isCancelled || _ownerId != ownerId) return;
      _setStatus(key, ok ? 'downloaded' : 'failed');
    } catch (_) {
      if (!cancellation.isCancelled) _setStatus(key, 'failed');
    } finally {
      if (identical(_cancellations[key], cancellation)) _cancellations.remove(key);
      if (mounted && _ownerId == ownerId &&
          ref.read(downloadJobStatusProvider)[key] != 'paused') {
        state = Map<String, double>.of(state)..remove(key);
      }
    }
  }

  Future<void> download(BzTrack track) async {
    final ownerId = _ownerId;
    if (ownerId == null) return;
    if (state.containsKey(track.id) || ['downloading', 'downloaded'].contains(ref.read(downloadJobStatusProvider)[track.id])) return;
    _tracks[track.id] = track;
    final cancellation = DownloadCancellation();
    _cancellations[track.id] = cancellation;
    _setStatus(track.id, 'downloading');

    try {
      final preferences = await DownloadPreferencesStore().load();
      final network = await Connectivity().checkConnectivity();
      final onWifi = network.contains(ConnectivityResult.wifi);
      final onMobile = network.contains(ConnectivityResult.mobile);
      if (!onWifi && (!onMobile || preferences.wifiOnly || !preferences.allowCellular)) {
        _setStatus(track.id, onMobile ? 'waiting_for_wifi' : 'waiting_for_network');
        return;
      }

      final auth = ref.read(authSessionProvider);
      if (auth is! AuthSignedIn || auth.userId != ownerId ||
          cancellation.isCancelled) {
        return;
      }

      final api = ref.read(authSessionProvider.notifier).api;
      if (api.accessToken == null) { _setStatus(track.id, 'failed'); return; }

      final catalogId = await _resolveCatalogId(api, track);
      if (cancellation.isCancelled) return;
      if (catalogId == null) { _setStatus(track.id, 'failed'); return; }

      final authorization = await api.authorizeDownload(
        trackId: catalogId,
        territory: ref.read(outboxTerritoryProvider),
      );
      if (cancellation.isCancelled) return;
      if (authorization['allowed'] != true) {
        _setStatus(track.id,
            downloadDenialStatus(authorization['reason']));
        // Do not log signed URLs or provider credentials.
        return;
      }

      // Legacy Breezze grant validation, now wired into the active downloader:
      // a preview or an absent/expired/off-contract offline lease is never
      // authorization for locally persistent music.
      final grant = AuthorizedDownloadGrant.fromResponse(authorization);
      if (grant == null) {
        _setStatus(track.id, 'failed');
        return;
      }
      final downloadUrl = grant.downloadUrl.toString();
      final rightsExpiry = grant.offlineLeaseExpiresAtUtc;

      state = {...state, track.id: 0.0};
      final dir = await downloadsDirectory(userId: auth.userId);
      final library = DownloadsLibrary(
        root: dir,
        lyrics: ref.read(lyricsProvider),
      );
      final ok = await library.download(
        track,
        downloadUrl: downloadUrl,
        ownerId: auth.userId,
        catalogTrackId: catalogId,
        rightsExpiresAtUtc: rightsExpiry,
        cancellation: cancellation,
        onProgress: (progress) {
          if (mounted && !cancellation.isCancelled && _ownerId == ownerId) {
            state = {...state, track.id: progress};
          }
        },
      );

      if (cancellation.isCancelled || _ownerId != ownerId) return;
      if (ok) {
        _setStatus(track.id, 'downloaded');
      } else if (!cancellation.isCancelled) {
        _setStatus(track.id, 'failed');
      }
    } catch (_) {
      if (!cancellation.isCancelled) _setStatus(track.id, 'failed');
    } finally {
      if (identical(_cancellations[track.id], cancellation)) _cancellations.remove(track.id);
      if (mounted && _ownerId == ownerId &&
          ref.read(downloadJobStatusProvider)[track.id] != 'paused') {
        state = Map<String, double>.of(state)..remove(track.id);
      }
    }
  }

  Future<String?> _resolveCatalogId(
    BreezzeApi api,
    BzTrack track,
  ) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: 'youtube',
      title: track.title,
      artistName: track.artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}
