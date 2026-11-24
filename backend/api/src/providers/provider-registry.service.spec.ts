import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { DeezerAdapter } from './deezer.adapter';

describe('ProviderRegistry', () => {
  beforeEach(() => jest.clearAllMocks());
  const makeAdapter = (providerId: string, priority: number, playback = false, availability = false) => ({
    providerId, displayName: providerId, adapterVersion: '1.0.0', priority, enabled: true,
    capabilities: { search: true, metadata: true, availability, playback, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  });
  const internal = makeAdapter('breezze_internal', 50, false, true);
  const youtube = makeAdapter('youtube_music', 100);
  const deezer = makeAdapter('deezer', 110);
  const registry = () => new ProviderRegistry(
    internal as unknown as InternalCatalogAdapter,
    youtube as unknown as YtMusicAdapter,
    deezer as unknown as DeezerAdapter,
  );

  it('searches only the Breezze canonical catalog, YouTube Music and Deezer with partial-failure isolation', async () => {
    internal.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'licensed-1' }] });
    youtube.search.mockResolvedValue({ kind: 'error', code: 'YTMUSIC_UNAVAILABLE', retryable: true, message: 'offline' });
    deezer.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'deezer-1' }] });
    const result = await registry().searchAll('  afrobeats  ');
    expect(result.query).toBe('afrobeats');
    expect(result.providers.map(item => item.providerId))
      .toEqual(['deezer', 'youtube_music', 'breezze_internal']);
    expect(internal.search).toHaveBeenCalledWith('afrobeats');
    expect(result.providers.find(item => item.providerId === 'breezze_internal')?.result)
      .toMatchObject({ kind: 'ok', value: [{ providerTrackId: 'licensed-1' }] });
    expect(result.providers.find(item => item.providerId === 'youtube_music')?.result)
      .toMatchObject({ kind: 'error', code: 'YTMUSIC_UNAVAILABLE' });
  });

  it('skips all upstreams for invalid search input', async () => {
    await expect(registry().searchAll('x')).resolves.toEqual({ query: 'x', providers: [] });
    expect(internal.search).not.toHaveBeenCalled();
    expect(youtube.search).not.toHaveBeenCalled();
    expect(deezer.search).not.toHaveBeenCalled();
  });

  it('contains only the requested external providers and never resolves their catalog metadata as full audio', () => {
    const instance = registry();
    expect(instance.list().map(item => item.providerId))
      .toEqual(['deezer', 'youtube_music', 'breezze_internal']);
    for (const id of ['youtube_music', 'deezer']) {
      expect(instance.get(id)?.capabilities).toMatchObject({
        search: true, metadata: true, playback: false, download: false,
      });
    }
    expect(instance.get('audius')).toBeUndefined();
    expect(instance.get('jamendo')).toBeUndefined();
    expect(instance.getPlaybackCandidates()).toEqual([]);
  });

  it('allows playback candidates only after explicit registration of a capable licensed provider', () => {
    const instance = registry();
    const licensed = {
      ...internal, providerId: 'licensed_provider',
      capabilities: { ...internal.capabilities, playback: true }, priority: 200,
    };
    instance.register(licensed as unknown as InternalCatalogAdapter);
    expect(instance.getPlaybackCandidates().map(item => item.providerId))
      .toEqual(['licensed_provider']);
  });
});
