import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter,
  ProviderCapabilities,
  ProviderTrack,
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
  readonly capabilities: ProviderCapabilities = {
    search: true,
    metadata: true,
    availability: false,
    playback: false,
    download: false,
  };

  private get baseUrl(): string {
    return (process.env.YTMUSIC_API_URL ?? 'http://127.0.0.1:8000').replace(/\/$/, '');
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    try {
      const url = new URL('/search', this.baseUrl);
      url.searchParams.set('q', q);
      url.searchParams.set('limit', '20');
      const response = await fetch(url, { signal: AbortSignal.timeout(6000) });
      if (!response.ok) {
        return providerError('YTMUSIC_SEARCH_FAILED', `Metadata provider returned HTTP ${response.status}`, response.status >= 500);
      }
      const payload = await response.json() as SearchPayload;
      if (!Array.isArray(payload.tracks)) {
        return providerError('YTMUSIC_INVALID_RESPONSE', 'Metadata provider returned an invalid search payload', false);
      }
      return providerOk(payload.tracks, 'YouTube Music metadata via ytmusicapi');
    } catch {
      return providerError('YTMUSIC_UNAVAILABLE', 'YouTube Music metadata provider is temporarily unavailable', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(providerTrackId)) {
      return providerError('INVALID_YTMUSIC_ID', 'Invalid YouTube Music track identifier', false);
    }
    try {
      const url = new URL(`/tracks/${encodeURIComponent(providerTrackId)}`, this.baseUrl);
      const response = await fetch(url, { signal: AbortSignal.timeout(6000) });
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
      return providerOk(payload.track, 'YouTube Music metadata via ytmusicapi');
    } catch {
      return providerError('YTMUSIC_UNAVAILABLE', 'YouTube Music metadata provider is temporarily unavailable', true);
    }
  }

  async getAvailability(): Promise<ProviderResult<{ available: boolean }>> {
    return providerUnsupported('YouTube Music metadata access does not establish streaming rights or playback availability');
  }
}
