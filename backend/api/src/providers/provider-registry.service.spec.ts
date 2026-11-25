import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { SpotifyAdapter } from './spotify.adapter';

describe('ProviderRegistry: Spotify music / YouTube videos', () => {
  beforeEach(() => jest.clearAllMocks());
  const makeAdapter = (providerId: string, priority: number, playback = false, availability = false) => ({
    providerId, displayName: providerId, adapterVersion: '1.0.0', priority, enabled: true,
    capabilities: { search: true, metadata: true, availability, playback, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  });
  const internal = makeAdapter('breezze_internal', 50, false, true);
  const spotify = makeAdapter('spotify', 220);
  const registry = () => new ProviderRegistry(
    internal as unknown as InternalCatalogAdapter,
    spotify as unknown as SpotifyAdapter,
  );

  it('searches Spotify and Breezze catalog independently; YouTube stays video-only', async () => {
    internal.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'licensed-1' }] });
    spotify.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'spotify-track-1' }] });
    const result = await registry().searchAll('  afrobeats  ');
    expect(result.query).toBe('afrobeats');
    expect(result.providers.map(item => item.providerId))
      .toEqual(['spotify', 'breezze_internal']);
    expect(spotify.search).toHaveBeenCalledWith('afrobeats');
    expect(result.providers[0].result).toMatchObject({
      kind: 'ok', value: [{ providerTrackId: 'spotify-track-1' }],
    });
  });

  it('skips upstreams for invalid input', async () => {
    await expect(registry().searchAll('x')).resolves.toEqual({ query: 'x', providers: [] });
    expect(internal.search).not.toHaveBeenCalled();
    expect(spotify.search).not.toHaveBeenCalled();
  });

  it('allows no YouTube, Deezer or Spotify native media grants', () => {
    const instance = registry();
    expect(instance.list().map(item => item.providerId)).toEqual(['spotify', 'breezze_internal']);
    expect(instance.get('youtube_music')).toBeUndefined();
    expect(instance.get('deezer')).toBeUndefined();
    expect(instance.get('audius')).toBeUndefined();
    expect(instance.get('spotify')?.capabilities).toMatchObject({
      search: true, metadata: true, playback: false, download: false,
    });
    expect(instance.getPlaybackCandidates()).toEqual([]);
  });

  it('isolates an external provider outage while preserving internal music', async () => {
    spotify.search.mockRejectedValue(new Error('SPOTIFY_UNAVAILABLE'));
    internal.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'licensed-1' }] });
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
