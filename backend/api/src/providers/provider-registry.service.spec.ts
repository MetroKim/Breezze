import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';

describe('ProviderRegistry', () => {
  const internal = {
    providerId: 'breezze_internal',
    displayName: 'Breezze Internal Catalog',
    adapterVersion: '1.0.0',
    priority: 50,
    enabled: true,
    capabilities: { search: true, metadata: true, availability: true, playback: false, download: false },
    search: jest.fn(),
    getTrack: jest.fn(),
    getAvailability: jest.fn(),
    resolvePlayback: jest.fn(),
  };
  const youtube = {
    providerId: 'youtube_music',
    displayName: 'YouTube Music',
    adapterVersion: '1.0.0',
    priority: 100,
    enabled: true,
    capabilities: { search: true, metadata: true, availability: false, playback: false, download: false },
    search: jest.fn(),
    getTrack: jest.fn(),
    getAvailability: jest.fn(),
    resolvePlayback: jest.fn(),
  };

  const registry = () => new ProviderRegistry(
    internal as unknown as InternalCatalogAdapter,
    youtube as unknown as YtMusicAdapter,
  );

  it('lists enabled providers in priority order with their declared capabilities', () => {
    expect(registry().list().map((provider) => provider.providerId))
      .toEqual(['youtube_music', 'breezze_internal']);
    expect(registry().list()[0].capabilities.playback).toBe(false);
  });

  it('never selects metadata-only providers as playback candidates', () => {
    expect(registry().getPlaybackCandidates()).toEqual([]);
  });

  it('selects only enabled providers that explicitly declare playback', () => {
    const playable = {
      ...internal,
      providerId: 'licensed_provider',
      capabilities: { ...internal.capabilities, playback: true },
      priority: 200,
    };
    const instance = registry();
    instance.register(playable as unknown as InternalCatalogAdapter);
    expect(instance.getPlaybackCandidates().map((provider) => provider.providerId))
      .toEqual(['licensed_provider']);
  });
});
