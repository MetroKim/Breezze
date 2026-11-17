import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';

/// Live download progress, keyed by track id: 0.0–1.0, removed on finish.
final downloadProgressProvider =
    StateNotifierProvider<DownloadsController, Map<String, double>>(
        DownloadsController.new);

/// Starts downloads via the DownloadsLibrary, tracking live progress that
/// any screen can watch.
class DownloadsController extends StateNotifier<Map<String, double>> {
  DownloadsController(this.ref) : super({});

  final Ref ref;

  Future<void> download(BzTrack track) async {
    // Never double-start the same track.
    if (state.containsKey(track.id)) return;
    state = {...state, track.id: 0.0};

    final dir = await downloadsDirectory();
    final library = DownloadsLibrary(
      root: dir,
      source: ref.read(youtubeSourceProvider),
      lyrics: ref.read(lyricsProvider),
    );

    final ok = await library.download(
      track,
      onProgress: (p) {
        if (mounted) state = {...state, track.id: p};
      },
    );

    // Remove from the in-progress map either way; the Downloads tab
    // refresh will show success. Failed downloads vanish with a warning
    // printed here rather than silently.
    if (mounted) {
      final next = Map<String, double>.of(state)..remove(track.id);
      state = next;
    }
    if (!ok) {
      print('download_failed: ${track.title}');
    }
  }
}
