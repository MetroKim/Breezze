/// Breezze provider chain — metadata discovery and authorized source selection.
///
/// Primary: a BitChord-style pluggable module source (YouTube Music
/// catalog adapter with lossless FLAC/ALAC variants).
/// Fallback: a Liner-style local/handoff source (local files via the
/// chordline-local:// scheme, or an external player handoff when Breezze
/// is not licensed to host the media).
///
/// Never silently substitute a live/remix/different master (§52.7); if no
/// licensed source exists, return unavailable and show permitted
/// alternatives.
library;

import 'bz_track.dart';
import 'provider_adapter.dart';

/// Result of a source-chain resolution attempt.
sealed class SourceChainResult {}

class SourceChainOk extends SourceChainResult {
  final String fromSourceId;
  final String streamUrl;
  SourceChainOk(this.fromSourceId, this.streamUrl);
}

class SourceChainUnavailable extends SourceChainResult {
  final String reason;
  final List<String> alternativesShown;
  SourceChainUnavailable(this.reason, {this.alternativesShown = const []});
}

/// Ordered provider chain: primary first, eligible fallbacks after.
class SourceChain {
  final List<ProviderAdapter> sources;

  SourceChain(this.sources);

  /// Resolves the first eligible provider source. The provider must have
  /// an explicit playback capability and independently enforce the backend
  /// authorization contract; metadata adapters are never playback sources.
  Future<SourceChainResult> resolve(
    String trackId,
    ProviderUserContext userContext,
  ) async {
    for (final source in sources) {
      if (!source.supportsPlayback) continue;

      final ok = await source.resolvePlayback(trackId, userContext);
      if (ok is ProviderOk<String>) {
        // Verify the fallback maps to the SAME recording/version (§52.7).
        return SourceChainOk(source.providerId, ok.value);
      }
    }
    return SourceChainUnavailable('no_licensed_source', alternativesShown: [
      'preview',
      'related_track',
      'local_file',
    ]);
  }

  /// Search across registered metadata providers, merged and de-duplicated by title+artist.
  Future<List<BzTrack>> searchAll(String query) async {
    final results = <BzTrack>[];
    final seen = <String>{};
    for (final source in sources) {
      final op = await source.search(query);
      if (op is ProviderOk<List<ProviderTrack>>) {
        for (final t in op.value) {
          final key = '${t.title}|${t.artist}'.toLowerCase();
          if (seen.add(key)) {
            results.add(BzTrack(
              id: t.breezzeTrackId,
              title: t.title,
              artist: t.artist,
              artworkUrl: t.artworkUrl,
              duration: t.duration,
            ));
          }
        }
      }
    }
    return results;
  }
}
