import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter,
  ProviderCapabilities,
  ProviderPlaybackRequest,
  ProviderPlaybackSource,
  ProviderTrack,
} from './provider-adapter.interface';
import { ProviderCacheService } from './provider-cache.service';
import {
  ProviderResult,
  providerError,
  providerOk,
  providerUnsupported,
} from './provider-result';

interface AudiusTrack {
  id?: string;
  title?: string;
  duration?: number;
  is_stream_gated?: boolean;
  isStreamGated?: boolean;
  allowed_api_keys?: string[];
  allowedApiKeys?: string[];
  user?: { name?: string; handle?: string };
  artwork?: { '150x150'?: string; '480x480'?: string; '1000x1000'?: string };
}

interface AudiusEnvelope<T> {
  data?: T;
}

@Injectable()
export class AudiusAdapter implements ProviderAdapter {
  readonly providerId = 'audius';
  readonly displayName = 'Audius';
  readonly adapterVersion = '1.0.0';
  readonly priority = 80;
  get enabled(): boolean {
    return process.env.AUDIUS_ENABLED !== 'false';
  }
  readonly capabilities: ProviderCapabilities = {
    search: true,
    metadata: true,
    availability: true,
    // Audius' official stream endpoint is used only for public, ungated
    // tracks returned by its API. Gated tracks fail closed per track.
    playback: true,
    download: false,
    albums: true,
    artists: true,
    playlists: true,
    charts: true,
  };

  private readonly baseUrl = (
    process.env.AUDIUS_API_URL ?? 'https://api.audius.co/v1'
  ).replace(/\/$/, '');

  constructor(private readonly cache: ProviderCacheService) {}

  private url(path: string, params: Record<string, string> = {}): URL {
    const url = new URL(path.startsWith('/') ? path.slice(1) : path, `${this.baseUrl}/`);
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }
    const apiKey = process.env.AUDIUS_API_KEY;
    if (apiKey) url.searchParams.set('api_key', apiKey);
    return url;
  }

  private async request<T>(url: URL): Promise<T> {
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) {
      throw new Error(`AUDIUS_HTTP_${response.status}`);
    }
    return await response.json() as T;
  }

  private mapTrack(track: AudiusTrack): ProviderTrack | null {
    if (!track.id || !track.title || !track.user?.name) return null;
    const artwork = track.artwork;
    return {
      providerTrackId: track.id,
      title: track.title,
      artist: track.user.name,
      artworkUrl:
        artwork?.['480x480'] ??
        artwork?.['150x150'] ??
        artwork?.['1000x1000'],
      durationSec:
        typeof track.duration === 'number' ? track.duration : undefined,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const key = `provider:audius:search:v1:${encodeURIComponent(q.toLowerCase())}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;

    try {
      const payload = await this.request<AudiusEnvelope<AudiusTrack[]>>(
        this.url('/tracks/search', { query: q, limit: '20' }),
      );
      if (!Array.isArray(payload.data)) {
        return providerError('AUDIUS_INVALID_RESPONSE', 'Audius returned an invalid track search response', false);
      }
      const tracks = payload.data
        .map((track) => this.mapTrack(track))
        .filter((track): track is ProviderTrack => track !== null);
      const result = providerOk(tracks, 'Audius public catalogue');
      await this.cache.set(key, result, 60);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Audius request failed';
      return providerError('AUDIUS_SEARCH_FAILED', message, true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!/^[A-Za-z0-9_-]{6,128}$/.test(providerTrackId)) {
      return providerError('INVALID_AUDIUS_TRACK_ID', 'Invalid Audius track identifier', false);
    }
    const key = `provider:audius:track:v1:${providerTrackId}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<AudiusEnvelope<AudiusTrack>>(
        this.url(`/tracks/${encodeURIComponent(providerTrackId)}`),
      );
      const track = payload.data ? this.mapTrack(payload.data) : null;
      if (!track) return providerError('AUDIUS_TRACK_NOT_FOUND', 'Audius track metadata was not found', false);
      const result = providerOk(track, 'Audius public catalogue');
      await this.cache.set(key, result, 300);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Audius request failed';
      return providerError('AUDIUS_TRACK_FAILED', message, true);
    }
  }

  async getAvailability(
    providerTrackId: string,
  ): Promise<ProviderResult<{ available: boolean }>> {
    try {
      const payload = await this.request<AudiusEnvelope<AudiusTrack>>(
        this.url(`/tracks/${encodeURIComponent(providerTrackId)}`),
      );
      const track = payload.data;
      const gated = track?.is_stream_gated ?? track?.isStreamGated ?? false;
      return providerOk({ available: Boolean(track?.id && !gated) });
    } catch {
      return providerError('AUDIUS_AVAILABILITY_FAILED', 'Could not verify Audius track availability', true);
    }
  }

  async resolvePlayback(
    request: ProviderPlaybackRequest,
  ): Promise<ProviderResult<ProviderPlaybackSource>> {
    if (!/^[A-Za-z0-9_-]{6,128}$/.test(request.providerTrackId)) {
      return providerError('INVALID_AUDIUS_TRACK_ID', 'Invalid Audius track identifier', false);
    }

    try {
      const payload = await this.request<AudiusEnvelope<AudiusTrack>>(
        this.url(`/tracks/${encodeURIComponent(request.providerTrackId)}`),
      );
      const track = payload.data;
      if (!track?.id) {
        return providerError('AUDIUS_TRACK_NOT_FOUND', 'Audius track was not found', false);
      }

      // Do not attempt to bypass programmable distribution. Gated releases
      // require creator-authorized signatures/conditions that Breezze does not
      // currently implement.
      const gated = track.is_stream_gated ?? track.isStreamGated ?? false;
      if (gated) {
        return providerUnsupported('AUDIUS_TRACK_GATED');
      }

      const streamUrl = this.url(
        `/tracks/${encodeURIComponent(request.providerTrackId)}/stream`,
      );
      // The official stream endpoint performs Audius' own API access checks
      // and redirects to the active content node. No audio is proxied/stored.
      return providerOk({
        url: streamUrl.toString(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
        mimeType: 'audio/mpeg',
      }, 'Streamed from Audius via its official API');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Audius stream resolution failed';
      return providerError('AUDIUS_PLAYBACK_RESOLVE_FAILED', message, true);
    }
  }
}
