/// Breezze metadata source chain.
///
/// Provider selection and playback resolution are server-side concerns.
/// This client-side chain only merges normalized catalogue search results
/// returned through Breezze's API.
library;

import 'bz_track.dart';
import 'provider_adapter.dart';

class SourceChain {
  final List<ProviderAdapter> sources;

  SourceChain(this.sources);

  /// Searches registered metadata adapters and de-duplicates by title+artist.
  Future<List<BzTrack>> searchAll(String query) async {
    final results = <BzTrack>[];
    final seen = <String>{};
    for (final source in sources) {
      final op = await source.search(query);
      if (op is ProviderOk<List<ProviderTrack>>) {
        for (final track in op.value) {
          final key = '${track.title}|${track.artist}'.toLowerCase();
          if (seen.add(key)) {
            results.add(BzTrack(
              id: track.breezzTrackId,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              duration: track.duration,
            ));
          }
        }
      }
    }
    return results;
  }
}
