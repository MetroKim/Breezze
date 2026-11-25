import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter, ProviderCapabilities, ProviderPlaybackRequest,
  ProviderPlaybackSource, ProviderTrack,
} from './provider-adapter.interface';
import { ProviderCacheService } from './provider-cache.service';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

interface DeezerTrack {
  id?: number;
  title?: string;
  duration?: number;
  link?: string;
  preview?: string;
  artist?: { name?: string };
  album?: { cover_medium?: string; cover_big?: string };
}
interface DeezerEnvelope<T> { data?: T[]; error?: { message?: string }; }

@Injectable()
export class DeezerAdapter implements ProviderAdapter {
  readonly providerId = 'deezer';
  readonly displayName = 'Deezer';
  readonly adapterVersion = '1.0.0';
  readonly priority = 110;
  get enabled(): boolean { return process.env.DEEZER_ENABLED !== 'false'; }
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: false, playback: false,
    download: false, albums: true, artists: true, playlists: false,
  };

  private readonly baseUrl = (process.env.DEEZER_API_URL ?? 'https://api.deezer.com').replace(/\/$/, '');
  constructor(private readonly cache: ProviderCacheService) {}

  private url(path: string, params: Record<string, string> = {}): URL {
    const url = new URL(path.replace(/^\//, ''), `${this.baseUrl}/`);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    return url;
  }

  private async request<T>(url: URL): Promise<T> {
    const response = await fetch(url, {
      headers: { accept: 'application/json', 'user-agent': 'Breezze/1.0' },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`DEEZER_HTTP_${response.status}`);
    const payload = await response.json() as T & { error?: { message?: string } };
    if (payload.error) throw new Error('DEEZER_API_REJECTED_REQUEST');
    return payload as T;
  }

  /**
   * Treat catalog JSON as untrusted data. One malformed Deezer record must
   * never erase the other valid results or expose arbitrary external links.
   */
  private mapTrack(item: unknown): ProviderTrack | null {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
    const track = item as DeezerTrack;
    if (typeof track.id !== 'number' || !Number.isSafeInteger(track.id) ||
        track.id <= 0 || typeof track.title !== 'string' ||
        !track.title.trim() || typeof track.artist?.name !== 'string' ||
        !track.artist.name.trim()) {
      return null;
    }

    const secureUrl = (value: unknown): URL | null => {
      if (typeof value !== 'string') return null;
      try {
        const url = new URL(value);
        return url.protocol === 'https:' && url.hostname.length > 0 &&
          !url.username && !url.password && !url.port ? url : null;
      } catch {
        return null;
      }
    };
    const artwork = secureUrl(track.album?.cover_big) ??
      secureUrl(track.album?.cover_medium);
    const deezerLink = secureUrl(track.link);
    const sourceUrl = deezerLink &&
      (deezerLink.hostname === 'deezer.com' ||
       deezerLink.hostname.endsWith('.deezer.com'))
      ? deezerLink.toString() : undefined;
    const clip = secureUrl(track.preview);
    const previewUrl = clip && clip.hostname.endsWith('.dzcdn.net')
      ? clip.toString() : undefined;
    return {
      providerTrackId: String(track.id),
      title: track.title.trim(),
      artist: track.artist.name.trim(),
      artworkUrl: artwork?.toString(),
      durationSec: typeof track.duration === 'number' &&
        Number.isFinite(track.duration) && track.duration > 0 &&
        track.duration < 24 * 3600 ? track.duration : undefined,
      sourceUrl,
      previewUrl,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    if (!this.enabled) return providerUnsupported('Deezer metadata provider is disabled');
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const key = `provider:deezer:search:v1:${encodeURIComponent(q.toLowerCase())}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<DeezerEnvelope<DeezerTrack>>(
        this.url('/search/track', { q, limit: '25' }),
      );
      if (!Array.isArray(payload.data)) return providerError('DEEZER_INVALID_RESPONSE', 'Deezer returned an invalid catalogue response', false);
      const result = providerOk(
        payload.data.map((item) => this.mapTrack(item)).filter((item): item is ProviderTrack => item !== null),
        'Track metadata supplied by Deezer; full-track playback is not granted by this API.',
      );
      await this.cache.set(key, result, 90);
      return result;
    } catch {
      return providerError('DEEZER_SEARCH_FAILED', 'Deezer catalogue search is temporarily unavailable', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!this.enabled) return providerUnsupported('Deezer metadata provider is disabled');
    if (!/^\d{1,20}$/.test(providerTrackId)) return providerError('INVALID_DEEZER_TRACK_ID', 'Invalid Deezer track identifier', false);
    const key = `provider:deezer:track:v1:${providerTrackId}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(key);
    if (cached) return cached;
    try {
      const track = this.mapTrack(await this.request<DeezerTrack>(this.url(`/track/${providerTrackId}`)));
      if (!track) return providerError('DEEZER_TRACK_NOT_FOUND', 'Deezer track metadata was not found', false);
      const result = providerOk(track, 'Track metadata supplied by Deezer; full-track playback is not granted by this API.');
      await this.cache.set(key, result, 300);
      return result;
    } catch {
      return providerError('DEEZER_TRACK_FAILED', 'Deezer track metadata is temporarily unavailable', true);
    }
  }

  async getAvailability(): Promise<ProviderResult<{ available: boolean }>> {
    return providerUnsupported('Deezer catalogue API access does not grant Breezze full-track streaming rights. Use an approved Deezer playback integration.');
  }

  async resolvePlayback(_request: ProviderPlaybackRequest): Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported('Deezer full-track playback requires an approved Deezer playback integration and user authorization.');
  }
}
