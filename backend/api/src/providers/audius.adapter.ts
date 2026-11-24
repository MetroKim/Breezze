import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter, ProviderCapabilities, ProviderPlaybackRequest,
  ProviderPlaybackSource, ProviderTrack,
} from './provider-adapter.interface';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

interface AudiusTrack {
  id?: string;
  title?: string;
  duration?: number;
  permalink?: string;
  is_available?: boolean;
  is_streamable?: boolean;
  is_stream_gated?: boolean;
  is_unlisted?: boolean;
  is_delete?: boolean;
  is_scheduled_release?: boolean;
  access?: { stream?: boolean };
  access_authorities?: string[] | null;
  allowed_api_keys?: string[] | null;
  stream_conditions?: unknown;
  artwork?: { '480x480'?: string };
  user?: { name?: string; is_available?: boolean; is_deactivated?: boolean };
}
interface AudiusResponse<T> { data?: T }

/**
 * Official Audius Open Music License provider. Streams remain hosted by
 * Audius; Breezze never caches, proxies, uploads or downloads its recordings.
 * An artist's API opt-out, gated, restricted, deleted or unpublished track
 * must be rejected at playback time even if discovery returned metadata.
 */
@Injectable()
export class AudiusAdapter implements ProviderAdapter {
  readonly providerId = 'audius';
  readonly displayName = 'Audius (public API streaming)';
  readonly adapterVersion = '1.0.0';
  readonly priority = 105;
  get enabled(): boolean {
    return process.env.AUDIUS_ENABLED === 'true' &&
      process.env.BREEZZE_NONCOMMERCIAL === 'true';
  }
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: true, playback: true,
    download: false, albums: false, artists: true,
    playlists: false, charts: true, genres: true,
  };
  private readonly endpoint = 'https://api.audius.co/v1/';

  private validId(id: string): boolean {
    return /^[A-Za-z0-9]{4,32}$/.test(id);
  }

  private async request<T>(path: string, parameters?: Record<string, string>)
      : Promise<AudiusResponse<T>> {
    const url = new URL(path, this.endpoint);
    if (parameters) {
      for (const [key, value] of Object.entries(parameters)) {
        url.searchParams.set(key, value);
      }
    }
    const response = await fetch(url, {
      headers: {
        accept: 'application/json',
        'user-agent': 'Breezze/1.0 (+https://breezze.app)',
      },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`AUDIUS_HTTP_${response.status}`);
    return await response.json() as AudiusResponse<T>;
  }

  private trackSourceUrl(track: AudiusTrack): string {
    const path = track.permalink;
    if (path && /^\/[A-Za-z0-9._/-]{2,350}$/.test(path) &&
        !path.startsWith('//') && !path.includes('..')) {
      return new URL(path, 'https://audius.co').toString();
    }
    // An exact track API URI remains a valid reference when an artist
    // has not published a canonical public permalink.
    return `https://api.audius.co/v1/tracks/${track.id}`;
  }

  private map(track: AudiusTrack): ProviderTrack | null {
    if (!track.id || !this.validId(track.id) || !track.title?.trim() ||
        !track.user?.name?.trim()) return null;
    return {
      providerTrackId: track.id,
      title: track.title.trim(),
      artist: track.user.name.trim(),
      artworkUrl: track.artwork?.['480x480'],
      durationSec: typeof track.duration === 'number' &&
          track.duration > 0 ? track.duration : undefined,
      sourceUrl: this.trackSourceUrl(track),
    };
  }

  private publicStreamingGrant(track: AudiusTrack): boolean {
    return track.is_available === true &&
      track.is_streamable === true &&
      track.access?.stream === true &&
      track.is_stream_gated === false &&
      track.is_unlisted === false &&
      track.is_delete === false &&
      track.is_scheduled_release !== true &&
      (track.access_authorities == null || track.access_authorities.length === 0) &&
      (track.allowed_api_keys == null || track.allowed_api_keys.length === 0) &&
      track.stream_conditions == null &&
      track.user?.is_available !== false &&
      track.user?.is_deactivated !== true;
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    if (!this.enabled) return providerUnsupported('AUDIUS_NOT_ENABLED');
    const normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) return providerOk([]);
    try {
      const data = await this.request<AudiusTrack[]>(
        'tracks/search', { query: normalized, limit: '20' },
      );
      if (!Array.isArray(data.data)) {
        return providerError('AUDIUS_INVALID_RESPONSE', 'Audius returned invalid metadata', false);
      }
      return providerOk(data.data
        .filter((row) => this.publicStreamingGrant(row))
        .map((row) => this.map(row))
        .filter((row): row is ProviderTrack => row !== null),
        'Public tracks from Audius; playback subject to the artist\'s live OML settings',
      );
    } catch {
      return providerError('AUDIUS_SEARCH_FAILED', 'Audius discovery unavailable', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!this.validId(providerTrackId)) {
      return providerError('AUDIUS_INVALID_TRACK_ID', 'Invalid Audius track ID', false);
    }
    if (!this.enabled) return providerUnsupported('AUDIUS_NOT_ENABLED');
    try {
      const res = await this.request<AudiusTrack>(
        `tracks/${providerTrackId}`,
      );
      const track = res.data && this.map(res.data);
      return track
        ? providerOk(track, 'Audius catalog metadata')
        : providerUnsupported('AUDIUS_TRACK_UNAVAILABLE');
    } catch {
      return providerError('AUDIUS_TRACK_FAILED', 'Audius track unavailable', true);
    }
  }

  async getAvailability(providerTrackId: string, _territory: string)
      : Promise<ProviderResult<{ available: boolean }>> {
    if (!this.validId(providerTrackId)) {
      return providerError('AUDIUS_INVALID_TRACK_ID', 'Invalid Audius track ID', false);
    }
    if (!this.enabled) return providerUnsupported('AUDIUS_NOT_ENABLED');
    try {
      const res = await this.request<AudiusTrack>(
        `tracks/${providerTrackId}`,
      );
      const track = res.data;
      if (!track || track.id !== providerTrackId ||
          !this.publicStreamingGrant(track)) {
        return providerOk({ available: false });
      }
      const artist = track.user?.name ?? 'Audius creator';
      const attribution = `Audius OML: "${track.title ?? 'Track'}" by ${artist}; ` +
        `source ${this.trackSourceUrl(track)}; ` +
        'public third-party API streaming only; no download or rehosting';
      return providerOk({ available: true }, attribution);
    } catch {
      return providerError('AUDIUS_AVAILABILITY_FAILED',
        'Unable to verify artist-controlled API streaming permission', true);
    }
  }

  async resolvePlayback(req: ProviderPlaybackRequest)
      : Promise<ProviderResult<ProviderPlaybackSource>> {
    if (!this.validId(req.providerTrackId)) {
      return providerError('AUDIUS_INVALID_TRACK_ID', 'Invalid Audius track ID', false);
    }
    if (!this.enabled) return providerUnsupported('AUDIUS_NOT_ENABLED');
    // The owning PlaybackResolveService has JUST called getAvailability
    // for this exact canonical mapping, territory and provider ID. The
    // attestation is generated server-side from that checked API response,
    // never accepted from user payload. Do not repeat the same upstream GET:
    // it increases rate-limit pressure and can expire the session on timeout.
    const proof = req.authorization.attribution;
    if (!proof?.startsWith('Audius OML: ') ||
        !proof.includes('source https://')) {
      return providerUnsupported('AUDIUS_OML_PUBLIC_STREAM_UNAVAILABLE');
    }
    return providerOk({
      url: new URL(`tracks/${req.providerTrackId}/stream`, this.endpoint).toString(),
      expiresAt: new Date(Date.now() + 30 * 60_000),
      mimeType: 'audio/mpeg',
      codec: 'mp3',
    }, proof);
  }
}
