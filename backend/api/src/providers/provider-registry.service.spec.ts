import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { DeezerAdapter } from './deezer.adapter';
import { JamendoAdapter } from './jamendo.adapter';

describe('ProviderRegistry', () => {
  beforeEach(() => jest.clearAllMocks());
  const makeAdapter = (providerId: string, priority: number, playback = false, availability = false) => ({
    providerId, displayName: providerId, adapterVersion: '1.0.0', priority, enabled: true,
    capabilities: { search: true, metadata: true, availability, playback, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  });
  const internal = makeAdapter('breezze_internal', 50, false, true);
  const youtube = makeAdapter('youtube_music', 100);
  const deezer = makeAdapter('deezer', 95);
  const jamendo = makeAdapter('jamendo', 110, true, true);

  const registry = () => new ProviderRegistry(
    internal as unknown as InternalCatalogAdapter,
    youtube as unknown as YtMusicAdapter,
    deezer as unknown as DeezerAdapter,
    jamendo as unknown as JamendoAdapter,
  );

  it('searches enabled external providers and preserves partial failures', async () => {
    youtube.search.mockResolvedValue({ kind: 'error', code: 'YTMUSIC_UNAVAILABLE', retryable: true, message: 'offline' });
    deezer.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'deezer-1' }] });
    jamendo.search.mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'jamendo-1' }] });
    const result = await registry().searchAll('  afrobeats  ');
    expect(result.query).toBe('afrobeats');
    expect(result.providers.map((item) => item.providerId))
      .toEqual(['youtube_music', 'deezer', 'jamendo', 'breezze_internal']);
    expect(internal.search).toHaveBeenCalledWith('afrobeats');
    expect(result.providers.find((item) => item.providerId === 'youtube_music')?.result)
      .toMatchObject({ kind: 'error', code: 'YTMUSIC_UNAVAILABLE' });
  });

  it('does not call upstream providers for an invalid federated query', async () => {
    const instance = registry();
    await expect(instance.searchAll('x')).resolves.toEqual({ query: 'x', providers: [] });
    expect(internal.search).not.toHaveBeenCalled();
    expect(youtube.search).not.toHaveBeenCalled();
    expect(deezer.search).not.toHaveBeenCalled();
    expect(jamendo.search).not.toHaveBeenCalled();
  });

  it('lists enabled providers and declares Deezer metadata-only', () => {
    const providers = registry().list();
    expect(providers.map((provider) => provider.providerId))
      .toEqual(['jamendo', 'youtube_music', 'deezer', 'breezze_internal']);
    expect(providers.find((provider) => provider.providerId === 'deezer')?.capabilities)
      .toMatchObject({ search: true, metadata: true, playback: false, availability: false });
  });

  it('selects only providers that explicitly declare both playback and availability', () => {
    expect(registry().getPlaybackCandidates().map((provider) => provider.providerId)).toEqual(['jamendo']);
    const licensed = { ...internal, providerId: 'licensed_provider',
      capabilities: { ...internal.capabilities, playback: true }, priority: 200 };
    const instance = registry();
    instance.register(licensed as unknown as InternalCatalogAdapter);
    expect(instance.getPlaybackCandidates().map((provider) => provider.providerId))
      .toEqual(['licensed_provider', 'jamendo']);
  });
});
