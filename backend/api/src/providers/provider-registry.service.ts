import { Injectable } from '@nestjs/common';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { AudiusAdapter } from './audius.adapter';
import { JamendoAdapter } from './jamendo.adapter';
import { ProviderAdapter } from './provider-adapter.interface';

// The registry owns provider identity, capability declaration, and health.
// Playback candidates are restricted to explicitly enabled playback adapters.
@Injectable()
export class ProviderRegistry {
  private readonly adapters = new Map<string, ProviderAdapter>();

  constructor(
    internal: InternalCatalogAdapter,
    youtubeMusic: YtMusicAdapter,
    audius: AudiusAdapter,
    jamendo: JamendoAdapter,
  ) {
    this.register(internal);
    this.register(youtubeMusic);
    this.register(audius);
    this.register(jamendo);
  }

  register(adapter: ProviderAdapter) {
    this.adapters.set(adapter.providerId, adapter);
  }

  get(providerId: string): ProviderAdapter | undefined {
    const adapter = this.adapters.get(providerId);
    return adapter?.enabled === false ? undefined : adapter;
  }

  list() {
    return [...this.adapters.values()]
      .filter((adapter) => adapter.enabled !== false)
      .sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0))
      .map((adapter) => ({
        providerId: adapter.providerId,
        displayName: adapter.displayName ?? adapter.providerId,
        adapterVersion: adapter.adapterVersion ?? 'unknown',
        priority: adapter.priority ?? 0,
        enabled: adapter.enabled !== false,
        capabilities: adapter.capabilities,
      }));
  }

  getPlaybackCandidates(): ProviderAdapter[] {
    return [...this.adapters.values()]
      .filter((adapter) =>
        adapter.enabled !== false &&
        adapter.capabilities.playback === true &&
        adapter.capabilities.availability === true &&
        typeof adapter.resolvePlayback === 'function',
      )
      .sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
  }
}
