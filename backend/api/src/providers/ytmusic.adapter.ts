import { Injectable } from '@nestjs/common';
import * as crypto from 'node:crypto';
import { ProviderCacheService } from './provider-cache.service';
import {
  ProviderAdapter,
  ProviderCapabilities,
  ProviderTrack,
  ProviderPlaybackRequest,
  ProviderPlaybackSource,
} from './provider-adapter.interface';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

interface SearchPayload {
  tracks?: ProviderTrack[];
}

interface TrackPayload {
  track?: ProviderTrack;
}

@Injectable()
export class YtMusicAdapter implements ProviderAdapter {
  readonly providerId = 'youtube_music';
  readonly displayName = 'YouTube Music';
  readonly adapterVersion = '1.0.0';
  readonly priority = 100;
  readonly enabled = true;
  readonly capabilities: ProviderCapabilities = {
    search: true,
    metadata: true,
    availability: false,
    playback: false,
    download: false,
  };

  private readonly inFlight = new Map<string, Promise<ProviderResult<unknown>>>();
  private consecutiveFailures = 0;
  private circuitOpenUntil = 0;
  private halfOpenProbeInFlight = false;

  constructor(private readonly cache: ProviderCacheService) {}

  /**
   * Coalesce identical cache misses inside this API process. Redis remains the
   * cross-process cache; this prevents one hot query from fanning out dozens
   * of identical sidecar calls on a single replica.
   */
  private async withCircuit<T>(
    operation: () => Promise<ProviderResult<T>>,
  ): Promise<ProviderResult<T>> {
    const now = Date.now();
    if (this.circuitOpenUntil > now) {
      return providerError('YTMUSIC_CIRCUIT_OPEN', 'YouTube Music metadata is temporarily paused after repeated upstream failures', true);
    }

    const halfOpen = this.circuitOpenUntil > 0;
    if (halfOpen && this.halfOpenProbeInFlight) {
      return providerError('YTMUSIC_CIRCUIT_OPEN', 'YouTube Music metadata recovery check is already in progress', true);
    }
    if (halfOpen) this.halfOpenProbeInFlight = true;

    try {
      const result = await operation();
      if (result.kind === 'ok') {
        this.consecutiveFailures = 0;
        this.circuitOpenUntil = 0;
      } else if (result.kind === 'error' && result.retryable) {
        this.recordUpstreamFailure();
      }
      return result;
    } finally {
      if (halfOpen) this.halfOpenProbeInFlight = false;
    }
  }

  private recordUpstreamFailure(): void {
    this.consecutiveFailures += 1;
    if (this.consecutiveFailures >= 5) {
      this.circuitOpenUntil = Date.now() + 30_000;
    }
  }

  private coalesce<T>(
    key: string,
    operation: () => Promise<ProviderResult<T>>,
  ): Promise<ProviderResult<T>> {
    const existing = this.inFlight.get(key);
    if (existing) return existing as Promise<ProviderResult<T>>;

    const pending = operation().finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, pending as Promise<ProviderResult<unknown>>);
    return pending;
  }

  /** Spread cache expirations so replicas do not stampede the metadata sidecar. */
  private cacheTtl(baseSeconds: number): number {
    const spread = Math.max(1, Math.floor(baseSeconds * 0.15));
    return baseSeconds + crypto.randomInt(-spread, spread + 1);
  }

  private get baseUrl(): string {
    return (process.env.YTMUSIC_API_URL ?? 'http://127.0.0.1:8000').replace(/\/$/, '');
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const queryHash = crypto.createHash('sha256').update(q.toLowerCase()).digest('hex');
    const cacheKey = `provider:youtube_music:search:v1:${queryHash}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(cacheKey);
    if (cached) return cached;
    return this.coalesce(cacheKey, () => this.withCircuit(async () => {
      try {
        const url = new URL('/search', this.baseUrl);
        url.searchParams.set('q', q);
        url.searchParams.set('limit', '20');
        const response = await fetch(url, { signal: AbortSignal.timeout(2500) });
        if (!response.ok) {
          return providerError('YTMUSIC_SEARCH_FAILED', `Metadata provider returned HTTP ${response.status}`, response.status >= 500 || response.status === 429);
        }
        const payload = await response.json() as SearchPayload;
        if (!Array.isArray(payload.tracks)) {
          return providerError('YTMUSIC_INVALID_RESPONSE', 'Metadata provider returned an invalid search payload', false);
        }
        const result = providerOk(payload.tracks, 'YouTube Music metadata via ytmusicapi');
        await this.cache.set(cacheKey, result, this.cacheTtl(60));
        return result;
      } catch {
        return providerError('YTMUSIC_UNAVAILABLE', 'YouTube Music metadata provider is temporarily unavailable', true);
      }
    }));
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(providerTrackId)) {
      return providerError('INVALID_YTMUSIC_ID', 'Invalid YouTube Music track identifier', false);
    }
    const cacheKey = `provider:youtube_music:track:v1:${providerTrackId}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(cacheKey);
    if (cached) return cached;
    return this.coalesce(cacheKey, () => this.withCircuit(async () => {
      try {
        const url = new URL(`/tracks/${encodeURIComponent(providerTrackId)}`, this.baseUrl);
        const response = await fetch(url, { signal: AbortSignal.timeout(3000) });
        if (response.status === 404) {
          return providerError('TRACK_NOT_FOUND', 'YouTube Music track metadata was not found', false);
        }
        if (!response.ok) {
          return providerError('YTMUSIC_TRACK_FAILED', `Metadata provider returned HTTP ${response.status}`, response.status >= 500);
        }
        const payload = await response.json() as TrackPayload;
        if (!payload.track?.providerTrackId || !payload.track.title || !payload.track.artist) {
          return providerError('YTMUSIC_INVALID_RESPONSE', 'Metadata provider returned an invalid track payload', false);
        }
        const result = providerOk(payload.track, 'YouTube Music metadata via ytmusicapi');
        await this.cache.set(cacheKey, result, this.cacheTtl(900));
        return result;
      } catch {
        return providerError('YTMUSIC_UNAVAILABLE', 'YouTube Music metadata provider is temporarily unavailable', true);
      }
    }));
  }

  async getAvailability(): Promise<ProviderResult<{ available: boolean }>> {
    return providerUnsupported('YouTube Music metadata access does not establish streaming rights or playback availability');
  }

  async resolvePlayback(
    _request: ProviderPlaybackRequest,
  ): Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported(
      'YouTube Music metadata access does not provide an authorized Breezze playback source',
    );
  }
}
