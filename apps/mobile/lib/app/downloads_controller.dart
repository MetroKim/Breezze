import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/auth/auth_session.dart';
import '../core/audio/authorized_download_grant.dart';
import '../core/audio/secure_downloads_library.dart';
import '../core/audio/playback_source_policy.dart';
import '../core/database/outbox_sync_service.dart';
import 'bootstrap.dart';
import 'download_preferences.dart';
import 'download_job_scope.dart';

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
    // A provider can outlive sign-out or an account switch. Do not expose
    // another listener's queued download titles or start their saved jobs.
    ref.listen<AuthState>(authSessionProvider, (previous, next) {
      final before = previous is AuthSignedIn ? previous.userId : null;
      final after = next is AuthSignedIn ? next.userId : null;
      if (before != after) _switchOwner(after);
    });
    _switchOwner(
      ref.read(authSessionProvider) case AuthSignedIn(:final userId)
          ? userId : null,
    );
    unawaited(_deleteLegacySharedJobFile());
  }

  final Ref ref;
  String? _ownerId;
  int _ownerGeneration = 0;
  Future<void> _jobWriteQueue = Future<void>.value();
  final Map<String, DownloadCancellation> _cancellations = {};
  final Map<String, BzTrack> _tracks = {};
  final Map<String, String> _videoTitles = {};

  void _switchOwner(String? nextOwner) {
    if (_ownerId == nextOwner) return;
    _ownerId = nextOwner;
    final generation = ++_ownerGeneration;
    for (final cancellation in _cancellations.values) {
      cancellation.cancel();
    }
    _cancellations.clear();
    _tracks.clear();
    _videoTitles.clear();
    if (mounted) {
      state = const <String, double>{};
      ref.read(downloadJobStatusProvider.notifier).state =
          const <String, String>{};
    }
    if (nextOwner != null) {
      unawaited(_restoreJobs(nextOwner, generation));
    }
  }

  Future<void> _deleteLegacySharedJobFile() async {
    // Earlier builds persisted unpartitioned titles on disk. Never import
    // them into an arbitrary signed-in listener's account.
    try {
      final base = await getApplicationSupportDirectory();
      final oldFile = File('${base.path}/Breezze/Downloads/jobs.json');
      if (await oldFile.exists()) await oldFile.delete();
    } catch (_) {
      // A failing or unavailable filesystem never blocks sign-in.
    }
  }

  Future<File> _jobsFile(String ownerId) async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory(
      '${dir.path}/Breezze/Downloads/${downloadJobOwnerDirectory(ownerId)}',
    );
    await folder.create(recursive: true);
    return File('${folder.path}/jobs.json');
  }

  Future<void> _persistJobs() {
    final ownerId = _ownerId;
    if (ownerId == null) return Future<void>.value();
    // Snapshot BEFORE async I/O so a later account switch cannot write the
    // next listener's queue under the previous listener's directory.
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
        'title': 'Video',
        'status': statuses[key] ?? 'queued',
      };
    }
    final data = jsonEncode(records);
    // Serialize writes and use a temporary file to avoid a torn JSON job
    // manifest during download progress bursts or app shutdown.
    _jobWriteQueue = _jobWriteQueue.then((_) async {
      final file = await _jobsFile(ownerId);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(data, flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    }).catchError((Object _) {});
    return _jobWriteQueue;
  }

  Future<void> _restoreJobs(String ownerId, int generation) async {
    try {
      final file = await _jobsFile(ownerId);
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          !mounted ||
          _ownerId != ownerId ||
          generation != _ownerGeneration) return;
      final statuses = <String, String>{};
      for (final entry in decoded.entries) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        if (item['kind'] == 'video' && entry.key.startsWith('video:')) {
          final videoAssetId = entry.key.substring('video:'.length);
          if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(videoAssetId)) {
            _videoTitles[videoAssetId] = 'Video';
            final saved = item['status'] as String? ?? 'failed';
            statuses[entry.key] = saved == 'downloading' ? 'paused' : saved;
          }
          continue;
        }
        final track = BzTrack(
          id: entry.key,
          title: item['title'] as String? ?? 'Unknown track',
          artist: item['artist'] as String? ?? 'Unknown artist',
          album: item['album'] as String?,
          artworkUrl: item['artworkUrl'] as String?,
          duration: Duration(milliseconds:
              (item['durationMs'] as num?)?.toInt() ?? 0),
          explicit: item['explicit'] == true,
        );
        _tracks[entry.key] = track;
        final saved = item['status'] as String? ?? 'failed';
        statuses[entry.key] = saved == 'downloading' ? 'paused' : saved;
      }
      if (mounted && _ownerId == ownerId &&
          generation == _ownerGeneration) {
        ref.read(downloadJobStatusProvider.notifier).state = statuses;
      }
    } catch (_) {
      // Corrupt or missing owner-scoped state must never expose other jobs.
    }
  }

  void _setStatus(
    String id,
    String status, {
    DownloadCancellation? cancellation,
  }) {
    if (!mounted || _ownerId == null ||
        (cancellation != null &&
         !identical(_cancellations[id], cancellation))) return;
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
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(videoAssetId)) return;
    final key = 'video:$videoAssetId';
    if (state.containsKey(key) ||
        ref.read(downloadJobStatusProvider)[key] == 'downloaded') return;
    _videoTitles[videoAssetId] = title;
    final cancellation = DownloadCancellation();
    _cancellations[key] = cancellation;
    _setStatus(key, 'downloading', cancellation: cancellation);
    try {
      final preferences = await DownloadPreferencesStore().load();
      final network = await Connectivity().checkConnectivity();
      final onWifi = network.contains(ConnectivityResult.wifi);
      final onMobile = network.contains(ConnectivityResult.mobile);
      if (!onWifi && (!onMobile || preferences.wifiOnly || !preferences.allowCellular)) {
        _setStatus(key, onMobile ? 'waiting_for_wifi' : 'waiting_for_network', cancellation: cancellation);
        return;
      }
      final auth = ref.read(authSessionProvider);
      if (auth is! AuthSignedIn) { _setStatus(key, 'failed', cancellation: cancellation); return; }
      final api = ref.read(authSessionProvider.notifier).api;
      if (api.accessToken == null) { _setStatus(key, 'failed', cancellation: cancellation); return; }
      final result = await api.authorizeVideoDownload(videoAssetId);
      if (cancellation.isCancelled) return;
      if (result['allowed'] != true || result['videoAssetId'] != videoAssetId ||
          result['mimeType'] != 'video/mp4') {
        _setStatus(key, 'failed', cancellation: cancellation);
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
        _setStatus(key, 'failed', cancellation: cancellation);
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
          if (mounted && identical(_cancellations[key], cancellation)) {
            state = {...state, key: value};
          }
        },
      );
      if (cancellation.isCancelled) return;
      _setStatus(key, ok ? 'downloaded' : 'failed', cancellation: cancellation);
    } catch (_) {
      if (!cancellation.isCancelled) _setStatus(key, 'failed', cancellation: cancellation);
    } finally {
      // An old listener's late Future must not erase another account's job.
      if (identical(_cancellations[key], cancellation)) {
        _cancellations.remove(key);
        if (mounted && ref.read(downloadJobStatusProvider)[key] != 'paused') {
          state = Map<String, double>.of(state)..remove(key);
        }
      }
    }
  }

  Future<void> download(BzTrack track) async {
    if (state.containsKey(track.id) || ['downloading', 'downloaded'].contains(ref.read(downloadJobStatusProvider)[track.id])) return;
    _tracks[track.id] = track;
    // Metadata-only songs and video/preview IDs cannot grant persistent
    // audio rights; reject before creating a transfer or asking the server.
    if (!canRequestOfflineDownload(track.id)) {
      _setStatus(track.id, 'rights_unavailable');
      return;
    }
    final cancellation = DownloadCancellation();
    _cancellations[track.id] = cancellation;
    _setStatus(track.id, 'downloading', cancellation: cancellation);

    try {
      final preferences = await DownloadPreferencesStore().load();
      final network = await Connectivity().checkConnectivity();
      final onWifi = network.contains(ConnectivityResult.wifi);
      final onMobile = network.contains(ConnectivityResult.mobile);
      if (!onWifi && (!onMobile || preferences.wifiOnly || !preferences.allowCellular)) {
        _setStatus(track.id, onMobile ? 'waiting_for_wifi' : 'waiting_for_network', cancellation: cancellation);
        return;
      }

      final auth = ref.read(authSessionProvider);
      if (auth is! AuthSignedIn) {
        _setStatus(track.id, 'login_required', cancellation: cancellation);
        return;
      }

      final api = ref.read(authSessionProvider.notifier).api;
      if (api.accessToken == null) { _setStatus(track.id, 'login_required', cancellation: cancellation); return; }

      // A non-provider ID identifies the canonical internal recording.
      // Its bytes and offline rights are still validated by the API.
      final catalogId = track.id;
      if (cancellation.isCancelled) return;

      final authorization = await api.authorizeDownload(
        trackId: catalogId,
        territory: ref.read(outboxTerritoryProvider),
      );
      if (cancellation.isCancelled) return;
      if (authorization['allowed'] != true) {
        // Authorization denial is not a transient network failure. Expose a
        // useful UI status without logging server reason/credential details.
        _setStatus(track.id, 'rights_unavailable', cancellation: cancellation);
        return;
      }

      // Legacy Breezze grant validation, now wired into the active downloader:
      // a preview or an absent/expired/off-contract offline lease is never
      // authorization for locally persistent music.
      final grant = AuthorizedDownloadGrant.fromResponse(authorization);
      if (grant == null) {
        _setStatus(track.id, 'invalid_grant', cancellation: cancellation);
        return;
      }
      final downloadUrl = grant.downloadUrl.toString();
      final rightsExpiry = grant.offlineLeaseExpiresAtUtc;

      state = {...state, track.id: 0.0};
      final dir = await downloadsDirectory(userId: auth.userId);
      final library = secureDownloadsLibrary(
        root: dir,
        lyrics: ref.read(lyricsProvider),
      );
      final ok = await library.download(
        track,
        downloadUrl: downloadUrl,
        ownerId: auth.userId,
        catalogTrackId: catalogId,
        rightsExpiresAtUtc: rightsExpiry,
        assetVersion: grant.assetVersion,
        cancellation: cancellation,
        onProgress: (progress) {
          if (mounted &&
              identical(_cancellations[track.id], cancellation)) {
            state = {...state, track.id: progress};
          }
        },
      );

      if (ok) {
        _setStatus(track.id, 'downloaded', cancellation: cancellation);
      } else if (!cancellation.isCancelled) {
        _setStatus(track.id, 'failed', cancellation: cancellation);
      }
    } catch (_) {
      if (!cancellation.isCancelled) _setStatus(track.id, 'failed', cancellation: cancellation);
    } finally {
      if (identical(_cancellations[track.id], cancellation)) {
        _cancellations.remove(track.id);
        if (mounted &&
            ref.read(downloadJobStatusProvider)[track.id] != 'paused') {
          state = Map<String, double>.of(state)..remove(track.id);
        }
      }
    }
  }

}
