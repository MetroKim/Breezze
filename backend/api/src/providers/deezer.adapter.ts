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
  isrc?: string;
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

  private mapTrack(track: DeezerTrack): ProviderTrack | null {
    if (!track.id || !track.title?.trim() || !track.artist?.name?.trim()) return null;
    return {
      providerTrackId: String(track.id),
      title: track.title.trim(),
      artist: track.artist.name.trim(),
      artworkUrl: track.album?.cover_big ?? track.album?.cover_medium,
      durationSec: typeof track.duration === 'number' && track.duration > 0 ? track.duration : undefined,
      sourceUrl: track.link,
      isrc: track.isrc,
      previewUrl: track.preview && /^https:\/\/[a-z0-9.-]+\.dzcdn\.net\//i.test(track.preview) ? track.preview : undefined,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const key = `provider:deezer:search:v2:${encodeURIComponent(q.toLowerCase())}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<DeezerEnvelope<DeezerTrack>>(
        this.url('/search/track', { q, limit: '50' }),
      );
      if (!Array.isArray(payload.data)) return providerError('DEEZER_INVALID_RESPONSE', 'Deezer returned an invalid catalogue response', false);
      const tracks = payload.data
        .map((item) => this.mapTrack(item))
        .filter((item): item is ProviderTrack => item !== null);
      // The public Deezer endpoint can return a few unrelated promoted tracks
      // before genuinely matching results. Rank literal title/artist matches
      // ahead of those entries, retaining Deezer's ordering within each band.
      const words = q.toLocaleLowerCase().split(/\s+/).filter(Boolean);
      const relevance = (track: ProviderTrack): number => {
        const searchable = (track.title + ' ' + track.artist).toLocaleLowerCase();
        return words.filter(word => searchable.includes(word)).length;
      };
      const indexed = tracks.map((track, index) => ({
        track, index, score: relevance(track),
      }));
      indexed.sort((a, b) => b.score - a.score || a.index - b.index);
      const result = providerOk(
        indexed.map(item => item.track),
        'Track metadata supplied by Deezer; full-track playback is not granted by this API.',
      );
      await this.cache.set(key, result, 90);
      return result;
    } catch {
      return providerError('DEEZER_SEARCH_FAILED', 'Deezer catalogue search is temporarily unavailable', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
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
