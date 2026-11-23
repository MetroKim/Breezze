/// Breezze download manager — spec §54, §30.4.
///
/// Download eligibility is decided by the backend (entitlement, territory,
/// rights) before a job is ever created (§54.2). Files live in
/// app-private storage with license metadata alongside each asset (§54.3).
library;

import 'dart:async';

/// Download job lifecycle (§54.1).
enum DownloadState { notDownloaded, queued, downloading, paused, downloaded, expired, failed, removed }

class DownloadJob {
  final String trackId;
  final String? playlistId;

  /// Quality tier requested; server picks the delivered variant.
  final String qualityTier;
  DownloadState state;
  double progress;
  String? localFilePath;
  final DateTime createdAtUtc;
  DateTime? completedAtUtc;

  DownloadJob({
    required this.trackId,
    this.playlistId,
    required this.qualityTier,
    this.state = DownloadState.queued,
    this.progress = 0,
  }) : createdAtUtc = DateTime.now().toUtc();

  bool get isPlayableOffline => state == DownloadState.downloaded;
}

/// Platform storage adapter — app-private storage on each OS.
abstract interface class DownloadStorage {
  /// App-private absolute directory for downloaded media.
  String get downloadsDir;

  /// Writes the bytes; returns the absolute file path written.
  Future<String> write(String trackId, List<int> bytes);
}

/// Backend authorization contract (§54.2). The server decides.
abstract interface class DownloadAuthorizer {
  /// Returns null when authorized, or the denial reason code.
  Future<String?> checkEligibility(String trackId, String userId);
}

/// Network fetcher seam — implemented over dio in the app layer.
abstract interface class DownloadFetcher {
  /// Streams chunks of the authorized download URL. Implementations must
  /// support byte-range resume.
  Stream<List<int>> download(String url, {int? startByte});
}

class DownloadManager {
  final DownloadAuthorizer authorizer;
  final DownloadStorage storage;
  final DownloadFetcher fetcher;

  final _jobs = <String, DownloadJob>{};
  final _updates = StreamController<List<DownloadJob>>.broadcast();

  DownloadManager({
    required this.authorizer,
    required this.storage,
    required this.fetcher,
  });

  /// All jobs, for the Downloads section UI.
  List<DownloadJob> get jobs => List.unmodifiable(_jobs.values);

  /// Bumped stream for UI rebuilds.
  Stream<List<DownloadJob>> get jobUpdates => _updates.stream;

  /// Queues a download after server-side eligibility (§54.2).
  Future<bool> queue({
    required String trackId,
    required String userId,
    required String qualityTier,
    String? playlistId,
  }) async {
    if (_jobs.containsKey(trackId)) return false;

    final denial = await authorizer.checkEligibility(trackId, userId);
    if (denial != null) return false;

    final job = DownloadJob(
      trackId: trackId,
      playlistId: playlistId,
      qualityTier: qualityTier,
    );
    _jobs[trackId] = job;
    _notify();
    _run(job);
    return true;
  }

  Future<void> pause(String trackId) async {
    final job = _jobs[trackId];
    if (job == null) return;
    job.state = DownloadState.paused;
    _notify();
  }

  Future<void> retry(String trackId) async {
    final job = _jobs[trackId];
    if (job == null || job.state != DownloadState.failed) return;
    job.state = DownloadState.downloading;
    job.progress = 0;
    _notify();
    await _run(job);
  }

  Future<void> remove(String trackId) async {
    final job = _jobs.remove(trackId);
    if (job == null) return;
    job.state = DownloadState.removed;
    _notify();
  }

  Future<void> _run(DownloadJob job) async {
    try {
      final bytes = <int>[];
      await for (final chunk in fetcher.download('download://${job.trackId}')) {
        if (job.state == DownloadState.paused) return;
        bytes.addAll(chunk);
        job.progress = (bytes.length / 500000).clamp(0, 1);
        job.state = DownloadState.downloading;
        _notify();
      }
      job.localFilePath = await storage.write(job.trackId, bytes);
      job.state = DownloadState.downloaded;
      job.completedAtUtc = DateTime.now().toUtc();
      _notify();
    } catch (_) {
      job.state = DownloadState.failed;
      _notify();
    }
  }

  void _notify() => _updates.add(List.of(_jobs.values));

  void dispose() => _updates.close();
}
