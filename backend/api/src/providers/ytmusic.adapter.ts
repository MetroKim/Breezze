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

export interface YtMusicArtist {
  artistId: string;
  name: string;
  artworkUrl?: string | null;
  subscribers?: string | null;
  rank?: string | number | null;
}

export interface YtMusicArtistSearch {
  source: string;
  artists: YtMusicArtist[];
}

export interface YtMusicArtistDetail {
  source: string;
  artist: { artistId: string; name: string; description?: string | null; artworkUrl?: string | null;
    subscribers?: string | null; topSongs: Array<{ providerTrackId: string; title: string; artworkUrl?: string | null }>;
    albums: Array<{ browseId: string; title: string; year?: string | null; artworkUrl?: string | null }> };
}

export interface YtMusicWatchQueue {
  source: 'youtube_music';
  seedVideoId: string;
  playlistId: string | null;
  tracks: ProviderTrack[];
  playbackAvailable: false;
}

export interface YtMusicCharts {
  source: string;
  country: string;
  artists: YtMusicArtist[];
  musicVideoPlaylists: Array<{ playlistId: string; title: string; artworkUrl?: string | null }>;
  songRankingAvailable: boolean;
}

@Injectable()
export class YtMusicAdapter implements ProviderAdapter {
  readonly providerId = 'youtube_music';
  readonly displayName = 'YouTube Music';
  readonly adapterVersion = '1.0.0';
  readonly priority = 100;
  get enabled(): boolean {
    return process.env.YTMUSIC_ENABLED !== 'false';
  }
  readonly capabilities: ProviderCapabilities = {
    search: true,
    metadata: true,
    availability: false,
    playback: false,
    download: false,
    artists: true,
    charts: true,
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

  /** Supplementary YouTube Music public metadata; never an audio entitlement. */
  private async fetchSupplemental<T>(
    cacheKey: string,
    resource: string,
    isValid: (payload: unknown) => payload is T,
    ttlSeconds: number,
  ): Promise<ProviderResult<T>> {
    if (!this.enabled) return providerUnsupported('YouTube Music metadata provider is disabled');
    const cached = await this.cache.get<ProviderResult<T>>(cacheKey);
    if (cached) return cached;
    return this.coalesce(cacheKey, () => this.withCircuit(async () => {
      try {
        const response = await fetch(new URL(resource, this.baseUrl), { signal: AbortSignal.timeout(4500) });
        if (!response.ok) {
          return providerError('YTMUSIC_METADATA_FAILED', `Metadata provider returned HTTP ${response.status}`,
            response.status >= 500 || response.status === 429);
        }
        const payload: unknown = await response.json();
        if (!isValid(payload)) {
          return providerError('YTMUSIC_INVALID_RESPONSE', 'Unexpected YouTube Music metadata response', false);
        }
        const result = providerOk(payload, 'YouTube Music metadata via sigma67/ytmusicapi; no full-song playback grant');
        await this.cache.set(cacheKey, result, this.cacheTtl(ttlSeconds));
        return result;
      } catch {
        return providerError('YTMUSIC_UNAVAILABLE', 'YouTube Music metadata temporarily unavailable', true);
      }
    }));
  }

  searchArtists(query: string): Promise<ProviderResult<YtMusicArtistSearch>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return Promise.resolve(providerOk({ source: 'youtube_music', artists: [] }));
    const hash = crypto.createHash('sha256').update(q.toLowerCase()).digest('hex');
    const url = new URL('/artists/search', this.baseUrl);
    url.searchParams.set('q', q);
    url.searchParams.set('limit', '20');
    return this.fetchSupplemental(`provider:youtube_music:artists:v1:${hash}`, url.pathname + url.search,
      (payload): payload is YtMusicArtistSearch =>
        typeof payload === 'object' && payload !== null &&
        Array.isArray((payload as YtMusicArtistSearch).artists), 180);
  }

  getArtist(artistId: string): Promise<ProviderResult<YtMusicArtistDetail>> {
    if (!/^[A-Za-z0-9_-]{10,64}$/.test(artistId)) {
      return Promise.resolve(providerError('INVALID_YTMUSIC_ARTIST_ID', 'Invalid artist identifier', false));
    }
    return this.fetchSupplemental(`provider:youtube_music:artist:v1:${artistId}`,
      `/artists/${encodeURIComponent(artistId)}`,
      (payload): payload is YtMusicArtistDetail =>
        typeof payload === 'object' && payload !== null &&
        typeof (payload as YtMusicArtistDetail).artist?.name === 'string' &&
        Array.isArray((payload as YtMusicArtistDetail).artist?.topSongs) &&
        Array.isArray((payload as YtMusicArtistDetail).artist?.albums), 900);
  }

  getCharts(country = 'ZZ'): Promise<ProviderResult<YtMusicCharts>> {
    const territory = country.toUpperCase();
    if (!/^[A-Z]{2}$/.test(territory)) {
      return Promise.resolve(providerError('INVALID_YTMUSIC_CHART_COUNTRY', 'Expected a two-letter country code or ZZ', false));
    }
    return this.fetchSupplemental(`provider:youtube_music:charts:v1:${territory}`,
      `/charts?country=${territory}`,
      (payload): payload is YtMusicCharts =>
        typeof payload === 'object' && payload !== null &&
        (payload as YtMusicCharts).country === territory &&
        Array.isArray((payload as YtMusicCharts).artists) &&
        Array.isArray((payload as YtMusicCharts).musicVideoPlaylists) &&
        typeof (payload as YtMusicCharts).songRankingAvailable === 'boolean', 300);
  }

  /** Get unofficial YouTube Music next-track suggestions, metadata only. */
  getWatchQueue(videoId: string, limit = 20): Promise<ProviderResult<YtMusicWatchQueue>> {
    if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) {
      return Promise.resolve(providerError('INVALID_YTMUSIC_ID', 'Expected an 11-character YouTube Music ID', false));
    }
    if (!Number.isInteger(limit) || limit < 1 || limit > 25) {
      return Promise.resolve(providerError('INVALID_YTMUSIC_QUEUE_LIMIT', 'Queue limit must be 1 to 25', false));
    }
    return this.fetchSupplemental(
      `provider:youtube_music:watch-queue:v1:${videoId}:${limit}`,
      `/watch-queue/${encodeURIComponent(videoId)}?limit=${limit}`,
      (payload): payload is YtMusicWatchQueue =>
        typeof payload === 'object' && payload !== null &&
        (payload as YtMusicWatchQueue).source === 'youtube_music' &&
        (payload as YtMusicWatchQueue).seedVideoId === videoId &&
        (payload as YtMusicWatchQueue).playbackAvailable === false &&
        Array.isArray((payload as YtMusicWatchQueue).tracks), 60,
    );
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
