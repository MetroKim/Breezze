import { SpotifyAdapter } from './spotify.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('Spotify-only artist discovery and detail', () => {
  const artistId = '0TnOYISbd1XYRBk9myaseg';
  const albumId = '2up3OPMp9Tb4dAKM2erWXQ';
  const trackId = '4iV5W9uYEdYUVa79Axb7Rh';
  const cache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
  };
  const env = {
    id: process.env.SPOTIFY_CLIENT_ID,
    secret: process.env.SPOTIFY_CLIENT_SECRET,
    enabled: process.env.SPOTIFY_ENABLED,
  };
  const requests: string[] = [];
  const latest = new Date().toISOString().slice(0, 10);

  const artist = {
    id: artistId, name: 'Breezze Test Singer',
    images: [{ url: 'https://i.scdn.co/image/artist' }],
    genres: ['Bongo Flava'], followers: { total: 1200 },
  };
  const album = {
    id: albumId, name: 'A Fresh Album', album_type: 'album',
    release_date: latest, total_tracks: 2,
    images: [{ url: 'https://i.scdn.co/image/album' }],
    artists: [{ id: artistId, name: artist.name }],
  };
  const song = {
    id: trackId, name: 'A Fresh Single',
    duration_ms: 180000,
    artists: [{ id: artistId, name: artist.name }],
    album: { images: [{ url: 'https://i.scdn.co/image/album' }] },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    requests.length = 0;
    process.env.SPOTIFY_CLIENT_ID = 'artist-test-client';
    process.env.SPOTIFY_CLIENT_SECRET = 'artist-test-secret';
    process.env.SPOTIFY_ENABLED = 'true';
    jest.spyOn(global, 'fetch').mockImplementation(async input => {
      const url = new URL(String(input));
      requests.push(url.pathname + url.search);
      if (url.hostname === 'accounts.spotify.com') {
        return { ok: true, json: async () => ({
          access_token: 'artist-test-token',
          token_type: 'Bearer',
          expires_in: 3600,
        }) } as Response;
      }
      const body = url.pathname === '/v1/artists/' + artistId
        ? artist
        : url.pathname === '/v1/artists/' + artistId + '/albums'
        ? { items: [album] }
        : url.pathname === '/v1/albums/' + albumId
        ? album
        : url.pathname === '/v1/albums/' + albumId + '/tracks'
        ? { items: [song] }
        : url.pathname === '/v1/search' && url.searchParams.get('type') === 'artist'
        ? { artists: { items: [
            { ...artist, name: 'Breezze Test Singer Tribute',
              id: '1111111111111111111111' }, artist,
          ] } }
        : url.pathname === '/v1/search' && url.searchParams.get('type') === 'track'
        ? { tracks: { items: [
            { ...song, id: '2222222222222222222222',
              artists: [{ id: '3333333333333333333333', name: 'Impersonator' }] },
            song,
          ] } }
        : null;
      return { ok: body !== null, status: body ? 200 : 404,
        json: async () => body } as Response;
    });
  });
  afterEach(() => {
    jest.restoreAllMocks();
    for (const [key, value] of Object.entries({
      SPOTIFY_CLIENT_ID: env.id,
      SPOTIFY_CLIENT_SECRET: env.secret,
      SPOTIFY_ENABLED: env.enabled,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  const adapter = () => new SpotifyAdapter(cache as unknown as ProviderCacheService);

  it('ranks exact Spotify artist before partial names, returning artist portraits', async () => {
    const result = await adapter().searchArtists('Breezze Test Singer');
    expect(result).toMatchObject({ kind: 'ok', value: [
      { id: artistId, name: artist.name, imageUrl: artist.images[0].url },
      { name: 'Breezze Test Singer Tribute' },
    ] });
    expect(requests.some(path => path.includes('type=artist') &&
      path.includes('limit=10'))).toBe(true);
  });

  it('builds songs, releases and artist data without removed top-tracks endpoint', async () => {
    const result = await adapter().getArtistPage(artistId);
    expect(result).toMatchObject({
      kind: 'ok',
      value: {
        artist: { id: artistId, name: artist.name },
        songs: [{ providerTrackId: trackId }],
        newReleases: [{ id: albumId, title: album.name }],
        albums: [{ id: albumId, title: album.name }],
        songStatus: 'ok', albumStatus: 'ok',
        tours: { status: 'unsupported', events: [] },
      },
    });
    expect(requests).toContain('/v1/artists/' + artistId);
    expect(requests.some(path => path.includes('/v1/artists/' + artistId + '/albums'))).toBe(true);
    expect(requests.some(path => path.includes('/v1/search') &&
      path.includes('type=track') && path.includes('limit=10'))).toBe(true);
    expect(requests.join(' ')).not.toContain('top-tracks');
    expect(requests.join(' ')).not.toContain('related-artists');
    expect(requests.join(' ')).not.toContain('/browse/new-releases');
  });

  it('only lists actual Spotify album tracks and never stream/download grants', async () => {
    const result = await adapter().getAlbumPage(albumId);
    expect(result).toMatchObject({ kind: 'ok', value: {
      album: { id: albumId }, tracks: [{ providerTrackId: trackId }],
    } });
    expect(JSON.stringify(result)).not.toContain('streamUrl');
    expect(JSON.stringify(result)).not.toContain('downloadUrl');
  });

  it('rejects malformed artist IDs before any Spotify request', async () => {
    const result = await adapter().getArtistPage('not-an-id');
    expect(result).toMatchObject({ kind: 'error', code: 'INVALID_SPOTIFY_ARTIST_ID' });
    expect(requests).toEqual([]);
  });
});
