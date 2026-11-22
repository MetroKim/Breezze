import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { AudiusAdapter } from './audius.adapter';
import { JamendoAdapter } from './jamendo.adapter';

describe('ProviderRegistry', () => {
  const internal = {
    providerId: 'breezze_internal',
    displayName: 'Breezze Internal Catalog',
    adapterVersion: '1.0.0',
    priority: 50,
    enabled: true,
    capabilities: { search: true, metadata: true, availability: true, playback: false, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  };
  const youtube = {
    providerId: 'youtube_music',
    displayName: 'YouTube Music',
    adapterVersion: '1.0.0',
    priority: 100,
    enabled: true,
    capabilities: { search: true, metadata: true, availability: false, playback: false, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  };
  const audius = {
    providerId: 'audius', displayName: 'Audius', adapterVersion: '1.0.0',
    priority: 120, enabled: true,
    capabilities: { search: true, metadata: true, availability: true, playback: true, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  };
  const jamendo = {
    providerId: 'jamendo', displayName: 'Jamendo', adapterVersion: '1.0.0',
    priority: 110, enabled: true,
    capabilities: { search: true, metadata: true, availability: true, playback: true, download: false },
    search: jest.fn(), getTrack: jest.fn(), getAvailability: jest.fn(), resolvePlayback: jest.fn(),
  };

  const registry = () => new ProviderRegistry(
    internal as unknown as InternalCatalogAdapter,
    youtube as unknown as YtMusicAdapter,
    audius as unknown as AudiusAdapter,
    jamendo as unknown as JamendoAdapter,
  );

  it('lists enabled providers in priority order with their declared capabilities', () => {
    expect(registry().list().map((provider) => provider.providerId))
      .toEqual(['audius', 'jamendo', 'youtube_music', 'breezze_internal']);
    expect(registry().list()[0].capabilities.playback).toBe(true);
  });

  it('selects only the configured playback providers and excludes metadata-only YouTube Music', () => {
    expect(registry().getPlaybackCandidates().map((provider) => provider.providerId))
      .toEqual(['audius', 'jamendo']);
  });

  it('selects only enabled providers that explicitly declare playback and availability', () => {
    const playable = {
      ...internal,
      providerId: 'licensed_provider',
      capabilities: { ...internal.capabilities, playback: true },
      priority: 200,
    };
    const instance = registry();
    instance.register(playable as unknown as InternalCatalogAdapter);
    expect(instance.getPlaybackCandidates().map((provider) => provider.providerId))
      .toEqual(['licensed_provider', 'audius', 'jamendo']);
  });
});
