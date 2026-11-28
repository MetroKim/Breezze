import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { SpotifyAdapter } from './spotify.adapter';
import { DeezerAdapter } from './deezer.adapter';
import { MusicBrainzAdapter } from './musicbrainz.adapter';
import { OpenSubsonicAdapter } from './opensubsonic.adapter';

describe('ProviderRegistry: Spotify and Deezer music / YouTube videos', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    musicbrainz.enabled = false;
    spotify.enabled = true;
    opensubsonic.enabled = false;
  });
  const makeAdapter = (providerId: string, priority: number, playback = false, availability = false) => ({
    providerId, displayName: providerId, adapterVersion: '1.0.0', priority, enabled: true,
    capabilities: { search: true, metadata: true, availability, playback, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  });
  const internal = makeAdapter('breezze_internal', 50, false, true);
  const spotify = makeAdapter('spotify', 220);
  const deezer = makeAdapter('deezer', 110);
  const musicbrainz = makeAdapter('musicbrainz', 70);
  const opensubsonic = makeAdapter('opensubsonic', 80, true, true);
  musicbrainz.enabled = false;
  opensubsonic.enabled = false;
  const registry = () => new ProviderRegistry(
    internal as unknown as InternalCatalogAdapter,
    spotify as unknown as SpotifyAdapter,
    deezer as unknown as DeezerAdapter,
    musicbrainz as unknown as MusicBrainzAdapter,
    opensubsonic as unknown as OpenSubsonicAdapter,
  );

  it('searches Spotify and Deezer independently; YouTube stays video-only', async () => {
    internal.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'licensed-1' }] });
    spotify.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'spotify-track-1' }] });
    deezer.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: '3135556' }] });
    const result = await registry().searchAll('  afrobeats  ');
    expect(result.query).toBe('afrobeats');
    expect(result.providers.map(item => item.providerId))
      .toEqual(['spotify', 'deezer', 'breezze_internal']);
    expect(spotify.search).toHaveBeenCalledWith('afrobeats');
    expect(deezer.search).toHaveBeenCalledWith('afrobeats');
    expect(result.providers[0].result).toMatchObject({
      kind: 'ok', value: [{ providerTrackId: 'spotify-track-1' }],
    });
  });

  it('returns separate Spotify/Deezer shelves with the original provider ranking', async () => {
    spotify.search.mockResolvedValue({kind:'ok',value:[{
      providerTrackId:'4iV5W9uYEdYUVa79Axb7Rh',title:'Song',artist:'Artist',
    }]});
    deezer.search.mockResolvedValue({kind:'ok',value:[{
      providerTrackId:'3135556',title:'Song',artist:'Artist',
    }]});
    const result = await registry().searchMusic('  Song   name ');
    expect(result.query).toBe('Song name');
    expect(result.partial).toBe(false);
    expect(result.providers.map(item => item.providerId)).toEqual(['spotify','deezer']);
    expect(result.providers[0].result).toMatchObject({kind:'ok',value:[{providerTrackId:'4iV5W9uYEdYUVa79Axb7Rh'}]});
    expect(result.providers[1].result).toMatchObject({kind:'ok',value:[{providerTrackId:'3135556'}]});
    // Without matching durations/ISRC, similarly named editions stay apart.
    expect(result.tracks).toHaveLength(2);
    expect(result.tracks.map(track => track.providerId)).toEqual(['spotify', 'deezer']);
    expect(internal.search).not.toHaveBeenCalled();
  });

  it('isolates a Spotify outage without discarding Deezer search results', async () => {
    spotify.search.mockRejectedValue(new Error('upstream down'));
    deezer.search.mockResolvedValue({kind:'ok',value:[{providerTrackId:'3135556'}]});
    const response = await registry().searchMusic('afrobeats');
    expect(response.partial).toBe(true);
    expect(response.providers[0].result).toMatchObject({kind:'error',code:'MUSIC_PROVIDER_UNAVAILABLE'});
    expect(response.providers[1].result).toMatchObject({kind:'ok',value:[{providerTrackId:'3135556'}]});
    expect(response.tracks.map(track => track.providerId)).toEqual([]);
    // This mock lacks title/artist, so no fabricated search row is produced.
  });

  it('coalesces concurrent typeahead requests for the same normalized query', async () => {
    let finishSpotify!: (result: any) => void;
    spotify.search.mockImplementation(() => new Promise(resolve => {
      finishSpotify = resolve;
    }));
    deezer.search.mockResolvedValue({kind:'ok',value:[]});
    const instance = registry();
    const first = instance.searchMusic('  Jazz   Trio ');
    const second = instance.searchMusic('jazz trio');
    expect(first).toBe(second);
    await Promise.resolve();
    await Promise.resolve();
    expect(spotify.search).toHaveBeenCalledTimes(1);
    expect(deezer.search).toHaveBeenCalledTimes(1);
    finishSpotify({kind:'ok',value:[{providerTrackId:'spotify-1'}]});
    const result = await first;
    expect(result.partial).toBe(false);
    expect(result.query).toBe('Jazz Trio');
  });

  it('serves Deezer immediately when no Spotify credentials are configured', async () => {
    spotify.enabled = false;
    deezer.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: '3135556' }] });
    const result = await registry().searchMusic('Bongo Flava');
    expect(result.partial).toBe(false);
    expect(result.providers.map(shelf => shelf.providerId)).toEqual(['deezer']);
    expect(result.providers[0].result).toMatchObject({
      kind: 'ok', value: [{ providerTrackId: '3135556' }],
    });
    expect(spotify.search).not.toHaveBeenCalled();
  });

  it('uses clearly attributed keyless MusicBrainz fallback only if catalogs find nothing', async () => {
    spotify.enabled = false;
    musicbrainz.enabled = true;
    deezer.search.mockResolvedValue({ kind: 'ok', value: [] });
    musicbrainz.search.mockResolvedValue({ kind: 'ok', value: [{
      providerTrackId: '26c1620c-fd33-4414-a202-6aabbe2303be',
      title: 'Demo Track', artist: 'Demo Artist',
    }] });
    const result = await registry().searchMusic('Demo Track');
    expect(result.partial).toBe(false);
    expect(result.providers.map(shelf => shelf.providerId))
      .toEqual(['deezer', 'musicbrainz']);
    expect(result.providers[1].result).toMatchObject({
      kind: 'ok', value: [{ title: 'Demo Track' }],
    });
    expect(spotify.search).not.toHaveBeenCalled();
  });

  it('never uses backup catalog when Deezer already has matching songs', async () => {
    spotify.enabled = false;
    musicbrainz.enabled = true;
    deezer.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: '42' }] });
    const result = await registry().searchMusic('Music');
    expect(result.providers.map(shelf => shelf.providerId)).toEqual(['deezer']);
    expect(musicbrainz.search).not.toHaveBeenCalled();
  });

  it('does not spend upstream search quota for invalid music queries', async () => {
    const instance = registry();
    const result = await instance.searchMusic('x');
    expect(result).toEqual({query:'x',providers:[],tracks:[],partial:false});
    expect(spotify.search).not.toHaveBeenCalled();
    expect(deezer.search).not.toHaveBeenCalled();
  });

  it('skips upstreams for invalid input', async () => {
    await expect(registry().searchAll('x')).resolves.toEqual({ query: 'x', providers: [] });
    expect(internal.search).not.toHaveBeenCalled();
    expect(spotify.search).not.toHaveBeenCalled();
    expect(deezer.search).not.toHaveBeenCalled();
  });

  it('allows no YouTube, Spotify or Deezer unauthorized native full-track grants', () => {
    const instance = registry();
    expect(instance.list().map(item => item.providerId)).toEqual(['spotify', 'deezer', 'breezze_internal']);
    expect(instance.get('youtube_music')).toBeUndefined();
    expect(instance.get('deezer')?.capabilities).toMatchObject({
      search: true, metadata: true, playback: false, download: false,
    });
    expect(instance.get('audius')).toBeUndefined();
    expect(instance.get('spotify')?.capabilities).toMatchObject({
      search: true, metadata: true, playback: false, download: false,
    });
    expect(instance.getPlaybackCandidates()).toEqual([]);
  });

  it('isolates an external provider outage while preserving internal music', async () => {
    spotify.search.mockRejectedValue(new Error('SPOTIFY_UNAVAILABLE'));
    internal.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'licensed-1' }] });
    deezer.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: '3135556' }] });
    const result = await registry().searchAll('piano');
    expect(result.providers[0].result).toMatchObject({
      kind: 'error', code: 'PROVIDER_SEARCH_FAILED',
    });
    expect(result.providers[1].result).toMatchObject({ kind: 'ok' });
  });

  it('allows only explicitly rights-cleared backend stream candidates', () => {
    const instance = registry();
    instance.register({
      ...internal,
      providerId: 'separately_licensed',
      capabilities: { ...internal.capabilities, playback: true },
      priority: 250,
    } as unknown as InternalCatalogAdapter);
    expect(instance.getPlaybackCandidates().map(item => item.providerId))
      .toEqual(['separately_licensed']);
  });
});
