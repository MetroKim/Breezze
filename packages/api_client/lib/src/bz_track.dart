/// Breezze catalog track model — one canonical entity for every source.
///
/// Provider IDs and canonical Breezze IDs are kept distinct by the
/// backend mapping layer. A catalogue model never carries a raw stream URL;
/// playback goes through Breezze's authorized playback resolver.
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

