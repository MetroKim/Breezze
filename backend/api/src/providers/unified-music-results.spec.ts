import { unifiedMusicResults, MusicSearchShelf } from './unified-music-results';
import { ProviderTrack } from './provider-adapter.interface';

const shelf = (
  providerId: string,
  rows: ProviderTrack[],
): MusicSearchShelf => ({
  providerId,
  displayName: providerId,
  result: { kind: 'ok', value: rows },
});

const spotify: ProviderTrack = {
  providerTrackId: '4iV5W9uYEdYUVa79Axb7Rh',
  title: 'Song Name',
  artist: 'Artist One',
  durationSec: 213,
  isrc: 'USRC17607839',
  sourceUrl: 'https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh',
};
const deezer: ProviderTrack = {
  providerTrackId: '3135556',
  title: 'Song Name',
  artist: 'Artist One',
  durationSec: 214,
  isrc: 'US-RC1-76-07839',
  sourceUrl: 'https://www.deezer.com/track/3135556',
};

describe('unified music recording identity, never stream authorization', () => {
  it('shows a shared recording only once and preserves Spotify primary identity', () => {
    const result = unifiedMusicResults([
      shelf('deezer', [deezer]), shelf('spotify', [spotify]),
    ]);
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      providerId: 'spotify',
      providerTrackId: spotify.providerTrackId,
      sourceUrl: spotify.sourceUrl,
      alternateCatalogIds: [
        { providerId: 'deezer', providerTrackId: '3135556' },
      ],
    });
    expect(result[0].sourceUrl).not.toBe(deezer.sourceUrl);
  });

  it('uses Deezer for an unmatched recording, with Spotify songs first', () => {
    const other: ProviderTrack = {
      providerTrackId: '222',
      title: 'Different Song',
      artist: 'Another Artist',
      durationSec: 190,
    };
    expect(unifiedMusicResults([
      shelf('deezer', [deezer, other]), shelf('spotify', [spotify]),
    ]).map(track => track.providerId)).toEqual(['spotify', 'deezer']);
  });

  it('still returns Deezer when Spotify is unavailable', () => {
    const result = unifiedMusicResults([
      { providerId: 'spotify', displayName: 'Spotify', result: {
        kind: 'error', code: 'UNAVAILABLE', message: 'down', retryable: true,
      }},
      shelf('deezer', [deezer]),
    ]);
    expect(result).toMatchObject([{ providerId: 'deezer', providerTrackId: '3135556' }]);
  });

  it('matches equal title and artist with near durations if ISRC is missing', () => {
    const result = unifiedMusicResults([
      shelf('spotify', [{ ...spotify, isrc: undefined }]),
      shelf('deezer', [{ ...deezer, isrc: undefined, title: 'SONG  NAME' }]),
    ]);
    expect(result).toHaveLength(1);
  });

  it('keeps remix, live, conflicting ISRC and unknown-duration variants separate', () => {
    expect(unifiedMusicResults([
      shelf('spotify', [spotify]),
      shelf('deezer', [{ ...deezer, isrc: 'GBAYE6800011' }]),
    ])).toHaveLength(2);
    expect(unifiedMusicResults([
      shelf('spotify', [{ ...spotify, isrc: undefined }]),
      shelf('deezer', [{ ...deezer, isrc: undefined, title: 'Song Name (Live)' }]),
    ])).toHaveLength(2);
    expect(unifiedMusicResults([
      shelf('spotify', [{ ...spotify, isrc: undefined, durationSec: undefined }]),
      shelf('deezer', [{ ...deezer, isrc: undefined, durationSec: undefined }]),
    ])).toHaveLength(2);
    expect(unifiedMusicResults([
      shelf('spotify', [{ ...spotify, isrc: undefined }]),
      shelf('deezer', [{ ...deezer, isrc: undefined, durationSec: 240 }]),
    ])).toHaveLength(2);
  });

  it('does not collapse unrelated artists or create stream/download grants', () => {
    const list = unifiedMusicResults([
      shelf('spotify', [spotify]),
      shelf('deezer', [{ ...deezer, artist: 'Someone Else', isrc: undefined }]),
    ]);
    expect(list).toHaveLength(2);
    expect(list.every(result => !('streamUrl' in result) && !('downloadUrl' in result))).toBe(true);
  });
});
