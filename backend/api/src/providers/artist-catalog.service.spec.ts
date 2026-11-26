import { ArtistCatalogService } from './artist-catalog.service';
import { SpotifyAdapter, SpotifyArtistPage } from './spotify.adapter';
import { DeezerAdapter, DeezerArtistSupplement } from './deezer.adapter';

const artistId = '0TnOYISbd1XYRBk9myaseg';
const spotifyPage: SpotifyArtistPage = {
  artist: {
    id: artistId,
    name: 'Test Singer',
    url: 'https://open.spotify.com/artist/' + artistId,
    genres: ['Afrobeats'],
  },
  songs: [], albums: [], newReleases: [],
  tours: { status: 'unsupported', events: [] },
  searchSuggestions: ['Test Singer Afrobeats'],
  songStatus: 'ok',
  albumStatus: 'ok',
};
const spotifySong = {
  providerTrackId: '4iV5W9uYEdYUVa79Axb7Rh',
  title: 'Test Single', artist: 'Test Singer',
  durationSec: 200, sourceUrl: 'https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh',
};
const deezerSupplement: DeezerArtistSupplement = {
  matchedArtistId: '11',
  matchedName: 'Test Singer',
  artistExtra: { fans: 3400, albumCount: 8, url: 'https://www.deezer.com/artist/11' },
  songs: [{
    providerId: 'deezer',
    providerTrackId: '3135556',
    title: 'Other Single',
    artist: 'Test Singer',
    durationSec: 210,
    sourceUrl: 'https://www.deezer.com/track/3135556',
  }],
  albums: [{
    providerId: 'deezer', id: '123', title: 'First Album', type: 'album',
    releaseDate: new Date().toISOString().slice(0, 10),
    trackCount: 8, url: 'https://www.deezer.com/album/123',
  }],
  relatedArtists: [{
    providerId: 'deezer', id: '555',
    name: 'Related Singer', url: 'https://www.deezer.com/artist/555',
  }],
  songStatus: 'ok', albumStatus: 'ok', relatedStatus: 'ok',
};

describe('ArtistCatalogService: Spotify primary, Deezer scoped fallback', () => {
  const priorEnv = process.env.NODE_ENV;
  const priorApproved = process.env.ARTIST_DEEZER_FALLBACK_APPROVED;
  const spotify = { getArtistPage: jest.fn() };
  const deezer = { getArtistSupplement: jest.fn() };
  const service = () => new ArtistCatalogService(
    spotify as unknown as SpotifyAdapter,
    deezer as unknown as DeezerAdapter,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.NODE_ENV = 'test';
    delete process.env.ARTIST_DEEZER_FALLBACK_APPROVED;
    spotify.getArtistPage.mockResolvedValue({
      kind: 'ok', value: { ...spotifyPage }, attribution: 'Spotify metadata',
    });
    deezer.getArtistSupplement.mockResolvedValue({
      kind: 'ok', value: deezerSupplement,
    });
  });
  afterAll(() => {
    if (priorEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = priorEnv;
    if (priorApproved === undefined) delete process.env.ARTIST_DEEZER_FALLBACK_APPROVED;
    else process.env.ARTIST_DEEZER_FALLBACK_APPROVED = priorApproved;
  });

  it('uses Deezer only when the Spotify song or album section has no results', async () => {
    const result = await service().getArtistPage(artistId);
    expect(result).toMatchObject({
      kind: 'ok',
      value: {
        artist: { id: artistId, name: 'Test Singer' },
        songs: [{ providerId: 'deezer', providerTrackId: '3135556' }],
        albums: [{ providerId: 'deezer', id: '123' }],
        relatedArtists: [{ name: 'Related Singer' }],
        songSource: 'deezer', albumSource: 'deezer',
        sourceMatch: 'unique_exact_name',
      },
    });
    expect(deezer.getArtistSupplement).toHaveBeenCalledWith('Test Singer');
    expect(JSON.stringify(result)).not.toContain('streamUrl');
  });

  it('never mixes Spotify and Deezer track IDs inside populated song and release sections', async () => {
    spotify.getArtistPage.mockResolvedValue({
      kind: 'ok', value: {
        ...spotifyPage,
        songs: [spotifySong],
        albums: [{ id: '2up3OPMp9Tb4dAKM2erWXQ',
          title: 'Spotify Album', type: 'album', releaseDate: '2024-01-01',
          trackCount: 7, url: 'https://open.spotify.com/album/2up3OPMp9Tb4dAKM2erWXQ' }],
      },
    });
    const result = await service().getArtistPage(artistId);
    expect(result).toMatchObject({
      kind: 'ok', value: {
        songs: [{ providerTrackId: spotifySong.providerTrackId }],
        songSource: 'spotify', albumSource: 'spotify',
        albums: [{ title: 'Spotify Album' }],
      },
    });
    if (result.kind === 'ok') {
      expect(result.value.songs).toHaveLength(1);
      expect(result.value.albums).toHaveLength(1);
    }
  });

  it('does not use Deezer when its exact artist identification is ambiguous', async () => {
    deezer.getArtistSupplement.mockResolvedValue({
      kind: 'unsupported', reason: 'DEEZER_ARTIST_AMBIGUOUS',
    });
    const result = await service().getArtistPage(artistId);
    expect(result).toMatchObject({
      kind: 'ok', value: {
        songs: [], albums: [], sourceMatch: 'spotify_only',
        relatedArtists: [],
      },
    });
  });

  it('production defaults to no mixed-catalog page without partner approval', async () => {
    process.env.NODE_ENV = 'production';
    const result = await service().getArtistPage(artistId);
    expect(result).toMatchObject({
      kind: 'ok', value: {
        songSource: 'spotify', albumSource: 'spotify',
        relatedStatus: 'disabled', sourceMatch: 'spotify_only',
      },
    });
    expect(deezer.getArtistSupplement).not.toHaveBeenCalled();
  });

  it('allows explicitly approved production fallback only', async () => {
    process.env.NODE_ENV = 'production';
    process.env.ARTIST_DEEZER_FALLBACK_APPROVED = 'true';
    const result = await service().getArtistPage(artistId);
    expect(result).toMatchObject({kind:'ok',value:{songSource:'deezer'}});
  });

  it('does not turn a missing Spotify identity into an unverified Deezer artist', async () => {
    spotify.getArtistPage.mockResolvedValue({
      kind: 'unsupported', reason: 'SPOTIFY_NOT_CONFIGURED',
    });
    const result = await service().getArtistPage(artistId);
    expect(result).toMatchObject({kind:'unsupported'});
    expect(deezer.getArtistSupplement).not.toHaveBeenCalled();
  });
});
