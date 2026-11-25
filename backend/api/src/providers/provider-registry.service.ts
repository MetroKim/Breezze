import { Injectable } from '@nestjs/common';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { SpotifyAdapter } from './spotify.adapter';
import { DeezerAdapter } from './deezer.adapter';
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
    spotify: SpotifyAdapter,
    deezer: DeezerAdapter,
  ) {
    this.register(internal);
    this.register(spotify);
    this.register(deezer);
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

  private readonly musicSearchInFlight = new Map<string, Promise<{
    query: string;
    providers: Array<{
      providerId: string;
      displayName: string;
      result: ProviderResult<import('./provider-adapter.interface').ProviderTrack[]>;
    }>;
    partial: boolean;
  }>>();

  /**
   * Two independent music shelves for Breezze Search. Query Spotify and
   * Deezer concurrently, isolate provider failures, and dedupe simultaneous
   * typeahead requests (without storing cross-provider Spotify metadata).
   *
   * Spotify's catalog must stay in its own visibly attributed section rather
   * than being blended into Deezer rows; neither source authorizes playback.
   */
  searchMusic(query: string) {
    const normalized = (query ?? '').trim().replace(/\\s+/g, ' ');
    if (normalized.length < 2 || normalized.length > 120) {
      return Promise.resolve({ query: normalized, providers: [], partial: false });
    }
    const key = normalized.toLowerCase();
    const current = this.musicSearchInFlight.get(key);
    if (current) return current;
    const request = this.performMusicSearch(normalized).finally(() => {
      this.musicSearchInFlight.delete(key);
    });
    this.musicSearchInFlight.set(key, request);
    return request;
  }

  private async performMusicSearch(query: string) {
    const supported = ['spotify', 'deezer'] as const;
    const shelves = await Promise.all(supported.map(async (id) => {
      const adapter = this.get(id);
      const displayName = id === 'spotify' ? 'Spotify' : 'Deezer';
      if (!adapter) {
        return {
          providerId: id, displayName,
          result: { kind: 'unsupported' as const, reason: 'PROVIDER_NOT_CONFIGURED' },
        };
      }

      // A slow provider must not hold back the fast provider. Time-box
      // discovery, not playback. Spotify and Deezer clients impose their
      // own network abort deadlines and can finish cleanup after this bound.
      const result = await new Promise<ProviderResult<
        import('./provider-adapter.interface').ProviderTrack[]
      >>(resolve => {
        let finished = false;
        const complete = (value: ProviderResult<
          import('./provider-adapter.interface').ProviderTrack[]
        >) => {
          if (finished) return;
          finished = true;
          clearTimeout(timer);
          resolve(value);
        };
        const timer = setTimeout(() => complete({
          kind: 'error', code: 'MUSIC_PROVIDER_TIMEOUT',
          retryable: true, message: 'Music catalog provider timed out',
        }), 3800);
        Promise.resolve().then(() => adapter.search(query)).then(
          complete,
          () => complete({
            kind: 'error', code: 'MUSIC_PROVIDER_UNAVAILABLE',
            retryable: true, message: 'Music catalog provider unavailable',
          }),
        );
      });
      return { providerId: id, displayName, result };
    }));
    return {
      query,
      providers: shelves,
      partial: shelves.some(shelf => shelf.result.kind !== 'ok'),
    };
  }

  async searchAll(query: string) {
    const normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return { query: normalized, providers: [] };
    }
    // Spotify and Deezer are the only external MUSIC catalogs.
    // YouTube is reserved for visible music videos. Provider metadata is
    // never permission to download or decode a protected full recording.
    const adapters = [...this.adapters.values()].filter(
      (adapter) => adapter.enabled !== false && adapter.capabilities.search,
    ).sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
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
