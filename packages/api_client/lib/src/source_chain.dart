/// Breezze metadata source chain.
///
/// The server is authoritative for commercial catalog matching and playback
/// permissions. This client fallback never treats matching titles as media
/// grants and preserves each surviving track's original provider identity.
library;

import 'bz_track.dart';
import 'provider_adapter.dart';

class SourceChain {
  final List<ProviderAdapter> sources;

  SourceChain(this.sources);

  static String _normalize(String text) =>
      text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool _sameRecording(BzTrack a, ProviderTrack b) =>
      _normalize(a.title) == _normalize(b.title) &&
      _normalize(a.artist) == _normalize(b.artist) &&
      a.duration > Duration.zero && b.duration > Duration.zero &&
      (a.duration.inSeconds - b.duration.inSeconds).abs() <= 3;

  /// Metadata-only fallback. Keep distinct edits, remixes, covers and
  /// unknown-duration recordings separate; the first matching source wins.
  Future<List<BzTrack>> searchAll(String query) async {
    final results = <BzTrack>[];
    final seenIds = <String>{};
    for (final source in sources) {
      final op = await source.search(query);
      if (op is ProviderOk<List<ProviderTrack>>) {
        for (final track in op.value) {
          if (!seenIds.add(track.breezzeTrackId) ||
              results.any((current) => _sameRecording(current, track))) {
            continue;
          }
          results.add(BzTrack(
            id: track.breezzeTrackId,
            title: track.title,
            artist: track.artist,
            artworkUrl: track.artworkUrl,
            duration: track.duration,
          ));
        }
      }
    }
    return results;
  }
}
