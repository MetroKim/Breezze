/// Breezze catalog track model — one canonical entity for every source.
///
/// Canonical Breezze IDs are internal; provider IDs stay in the mapping
/// (§52.3). A track never carries a raw stream URL; playback goes through
/// the resolver.
library;

/// A canonical catalog track.
class BzTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration duration;
  final bool explicit;

  const BzTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    required this.duration,
    this.explicit = false,
  });

  BzTrack copyWith({String? title, String? artist}) => BzTrack(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: duration,
        explicit: explicit,
      );
}

/// Request-signing seam for the primary music source.
///
/// The parent projects both solve this: BitChord ships a native signer
/// module, Liner ships a WASM signer. Breezze defines the interface only;
/// the implementation is an installable adapter so the newest signing
/// scheme (poToken-era) can be swapped in without app changes.
abstract interface class SignerService {
  /// Produces the signature header for the request URL.
  Future<String> sign(String url, Map<String, String> params);
}
