import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/api/breezze_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_session.dart';
import '../core/database/database_providers.dart';
import '../core/database/outbox_sync_service.dart';
import 'bootstrap.dart';
import 'download_preferences.dart';

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
  DownloadsController(this.ref) : super({});

  final Ref ref;
  final Map<String, DownloadCancellation> _cancellations = {};
  final Map<String, BzTrack> _tracks = {};

  void _setStatus(String id, String status) {
    if (!mounted) return;
    final next = Map<String, String>.of(ref.read(downloadJobStatusProvider));
    next[id] = status;
    ref.read(downloadJobStatusProvider.notifier).state = next;
  }

  Future<void> pause(String trackId) async {
    _setStatus(trackId, 'paused');
    _cancellations[trackId]?.cancel();
  }

  Future<void> resume(String trackId) async {
    final track = _tracks[trackId];
    if (track != null) {
      final next = Map<String, double>.of(state)..remove(trackId);
      state = next;
      await download(track);
    }
  }

  Future<void> retry(String trackId) async {
    final track = _tracks[trackId];
    if (track != null) await download(track);
  }

  Future<void> cancel(String trackId) async {
    _setStatus(trackId, 'cancelled');
    _cancellations[trackId]?.cancel();
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

  Future<void> download(BzTrack track) async {
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
      if (auth is! AuthSignedIn) {
        _setStatus(track.id, 'failed');
        return;
      }

      final api = ref.read(authSessionProvider.notifier).api;
      if (api.accessToken == null) return;

      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return;

      final authorization = await api.authorizeDownload(
        trackId: catalogId,
        territory: ref.read(outboxTerritoryProvider),
      );
      if (authorization['allowed'] != true) {
        // ignore: avoid_print
        print('download_not_authorized: ${authorization['reason']}');
        return;
      }

      final downloadUrl = authorization['url'] as String?;
      if (downloadUrl == null || downloadUrl.isEmpty) return;
      // The server issues a bounded offline lease, capped by the actual rights end.
      // Keep the effective expiry in the local metadata so a device offline for
      // longer than the lease cannot continue playing indefinitely.
      final rightsExpiryRaw = (authorization['offlineLeaseExpiresAt']
          ?? authorization['rightsExpiresAt']) as String?;
      final rightsExpiry = rightsExpiryRaw == null
          ? null
          : DateTime.tryParse(rightsExpiryRaw)?.toUtc();
      if (rightsExpiryRaw != null && rightsExpiry == null) return;
      if (rightsExpiry != null && !rightsExpiry.isAfter(DateTime.now().toUtc())) {
        return;
      }

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
          if (mounted) state = {...state, track.id: progress};
        },
      );

      if (ok) {
        _setStatus(track.id, 'downloaded');
      } else if (!cancellation.isCancelled) {
        _setStatus(track.id, 'failed');
      }
    } catch (_) {
      if (!cancellation.isCancelled) _setStatus(track.id, 'failed');
    } finally {
      if (identical(_cancellations[track.id], cancellation)) _cancellations.remove(track.id);
      if (mounted) {
        if (ref.read(downloadJobStatusProvider)[track.id] != 'paused') {
          final next = Map<String, double>.of(state)..remove(track.id);
          state = next;
        }
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
