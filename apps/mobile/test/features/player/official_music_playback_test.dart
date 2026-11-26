import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/features/player/official_music_playback.dart';

void main() {
  test('official provider URLs use strict, canonical track identities', () {
    const spotify = 'bz:spotify:4uLU6hMCjMI75M1A2tKUQC';
    const deezer = 'bz:deezer:3135556';

    expect(OfficialMusicPlayback.canOpen(spotify), isTrue);
    expect(OfficialMusicPlayback.urlFor(spotify).toString(),
        'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC');
    expect(OfficialMusicPlayback.providerName(spotify), 'Spotify');

    expect(OfficialMusicPlayback.canOpen(deezer), isTrue);
    expect(OfficialMusicPlayback.urlFor(deezer).toString(),
        'https://www.deezer.com/track/3135556');
    expect(OfficialMusicPlayback.providerName(deezer), 'Deezer');
  });

  test('video, preview, and malformed IDs cannot become full-song links', () {
    for (final id in [
      'bz:youtube_music:dQw4w9WgXcQ',
      'bzv:dQw4w9WgXcQ',
      'bz:deezer_preview:3135556',
      'bz:spotify:invalid',
      'bz:deezer:123?redirect=https://example.com',
      'bz:spotify:4uLU6hMCjMI75M1A2tKUQC/evil',
      '',
    ]) {
      expect(OfficialMusicPlayback.canOpen(id), isFalse, reason: id);
      expect(OfficialMusicPlayback.urlFor(id), isNull, reason: id);
    }
  });
}
