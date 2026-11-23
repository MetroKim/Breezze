import { Injectable } from '@nestjs/common';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { DeezerAdapter } from './deezer.adapter';
import { JamendoAdapter } from './jamendo.adapter';
import { ProviderAdapter } from './provider-adapter.interface';
import { ProviderResult } from './provider-result';

// The registry owns provider identity, capabilities, and health.
// Metadata discovery is separate from playback authorization: only providers
// with an explicitly supported playback capability enter the playback resolver.
@Injectable()
export class ProviderRegistry {
  private readonly adapters = new Map<string, ProviderAdapter>();

  constructor(
    internal: InternalCatalogAdapter,
    youtubeMusic: YtMusicAdapter,
    deezer: DeezerAdapter,
    jamendo: JamendoAdapter,
  ) {
    this.register(internal);
    this.register(youtubeMusic);
    this.register(deezer);
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

  async searchAll(query: string) {
    const normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return { query: normalized, providers: [] };
    }
    const adapters = [...this.adapters.values()].filter(
      (adapter) => adapter.enabled !== false && adapter.capabilities.search,
    );
    const settled = await Promise.allSettled(
      adapters.map(async (adapter) => ({
        providerId: adapter.providerId,
        displayName: adapter.displayName ?? adapter.providerId,
        result: await adapter.search(normalized),
      })),
    );
    return {
      query: normalized,
      providers: settled.map((item, index) => item.status === 'fulfilled'
        ? item.value
        : {
            providerId: adapters[index].providerId,
            displayName: adapters[index].displayName ?? adapters[index].providerId,
            result: {
              kind: 'error' as const,
              code: 'PROVIDER_SEARCH_FAILED',
              retryable: true,
              message: 'This catalogue source is temporarily unavailable',
            } satisfies ProviderResult<unknown>,
          }),
    };
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
