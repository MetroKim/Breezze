import { Injectable } from '@nestjs/common';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { ProviderAdapter } from './provider-adapter.interface';

// Plan §7.5 — the registry owns provider identity, capability
// declaration, and health. Adapters are registered with explicit
// capability flags; playback is only ever declared by providers that
// authorize it in writing.
@Injectable()
export class ProviderRegistry {
  private readonly adapters = new Map<string, ProviderAdapter>();

  constructor(internal: InternalCatalogAdapter, youtubeMusic: YtMusicAdapter) {
    this.register(internal);
    this.register(youtubeMusic);
  }

  register(adapter: ProviderAdapter) {
    this.adapters.set(adapter.providerId, adapter);
  }

  get(providerId: string): ProviderAdapter | undefined {
    return this.adapters.get(providerId);
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

  /** Only providers explicitly enabled for playback may enter the resolver. */
  getPlaybackCandidates(): ProviderAdapter[] {
    return [...this.adapters.values()]
      .filter((adapter) =>
        adapter.enabled !== false &&
        adapter.capabilities.playback === true &&
        typeof adapter.resolvePlayback === 'function',
      )
      .sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
  }
}
