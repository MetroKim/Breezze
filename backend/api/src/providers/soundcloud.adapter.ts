import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter, ProviderCapabilities, ProviderPlaybackRequest,
  ProviderPlaybackSource, ProviderTrack,
} from './provider-adapter.interface';
import { ProviderCacheService } from './provider-cache.service';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

interface SoundCloudTrack {
  id?: number;
  title?: string;
  duration?: number;
  permalink_url?: string;
  artwork_url?: string;
  user?: { username?: string };
}
interface SoundCloudEnvelope { collection?: SoundCloudTrack[]; }

@Injectable()
export class SoundCloudAdapter implements ProviderAdapter {
  readonly providerId = 'soundcloud';
  readonly displayName = 'SoundCloud';
  readonly adapterVersion = '1.0.0';
  readonly priority = 90;
  get enabled(): boolean {
    return Boolean(process.env.SOUNDCLOUD_CLIENT_ID?.trim()) && process.env.SOUNDCLOUD_ENABLED !== 'false';
  }
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: false, playback: false,
    download: false, albums: false, artists: true, playlists: true,
  };

  private readonly baseUrl = (process.env.SOUNDCLOUD_API_URL ?? 'https://api-v2.soundcloud.com').replace(/\/$/, '');
  constructor(private readonly cache: ProviderCacheService) {}

  private url(path: string, params: Record<string, string> = {}): URL {
    const url = new URL(path.replace(/^\//, ''), `${this.baseUrl}/`);
    url.searchParams.set('client_id', process.env.SOUNDCLOUD_CLIENT_ID!.trim());
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    return url;
  }

  private async request<T>(url: URL): Promise<T> {
    const response = await fetch(url, {
      headers: { accept: 'application/json', 'user-agent': 'Breezze/1.0' },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`SOUNDCLOUD_HTTP_${response.status}`);
    return await response.json() as T;
  }

  private mapTrack(track: SoundCloudTrack): ProviderTrack | null {
    if (!track.id || !track.title?.trim() || !track.user?.username?.trim()) return null;
    const artwork = track.artwork_url?.replace('-large', '-t500x500');
    return {
      providerTrackId: String(track.id),
      title: track.title.trim(),
      artist: track.user.username.trim(),
      artworkUrl: artwork,
      durationSec: typeof track.duration === 'number' && track.duration > 0
        ? Math.round(track.duration / 1000) : undefined,
      sourceUrl: track.permalink_url,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    if (!this.enabled) return providerUnsupported('SOUNDCLOUD_NOT_CONFIGURED');
    const key = `provider:soundcloud:search:v1:${encodeURIComponent(q.toLowerCase())}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<SoundCloudEnvelope>(
        this.url('/search/tracks', { q, limit: '25' }),
      );
      if (!Array.isArray(payload.collection)) return providerError('SOUNDCLOUD_INVALID_RESPONSE', 'SoundCloud returned an invalid catalogue response', false);
      const result = providerOk(
        payload.collection.map((item) => this.mapTrack(item)).filter((item): item is ProviderTrack => item !== null),
        'Track metadata supplied by SoundCloud; playback remains subject to SoundCloud authorization and embed policy.',
      );
      await this.cache.set(key, result, 90);
      return result;
    } catch {
      return providerError('SOUNDCLOUD_SEARCH_FAILED', 'SoundCloud catalogue search is temporarily unavailable', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!/^\d{1,20}$/.test(providerTrackId)) return providerError('INVALID_SOUNDCLOUD_TRACK_ID', 'Invalid SoundCloud track identifier', false);
    if (!this.enabled) return providerUnsupported('SOUNDCLOUD_NOT_CONFIGURED');
    const key = `provider:soundcloud:track:v1:${providerTrackId}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(key);
    if (cached) return cached;
    try {
      const track = this.mapTrack(await this.request<SoundCloudTrack>(this.url(`/tracks/${providerTrackId}`)));
      if (!track) return providerError('SOUNDCLOUD_TRACK_NOT_FOUND', 'SoundCloud track metadata was not found', false);
      const result = providerOk(track, 'Track metadata supplied by SoundCloud; playback remains subject to SoundCloud authorization and embed policy.');
      await this.cache.set(key, result, 300);
      return result;
    } catch {
      return providerError('SOUNDCLOUD_TRACK_FAILED', 'SoundCloud track metadata is temporarily unavailable', true);
    }
  }

  async getAvailability(): Promise<ProviderResult<{ available: boolean }>> {
    return providerUnsupported('SoundCloud metadata access does not establish playback permission. Use an approved SoundCloud player or authorized stream grant.');
  }

  async resolvePlayback(_request: ProviderPlaybackRequest): Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported('SoundCloud playback must use an approved SoundCloud player or a currently authorized stream grant.');
  }
}
