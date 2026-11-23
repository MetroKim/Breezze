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

interface JamendoTrack {
  id?: string | number;
  name?: string;
  artist_name?: string;
  duration?: string | number;
  image?: string;
  album_image?: string;
  license_ccurl?: string;
  audiodownload_allowed?: boolean;
  shareurl?: string;
}

interface JamendoEnvelope<T> {
  headers?: { status?: string; code?: number; error_message?: string };
  results?: T[];
}

@Injectable()
export class JamendoAdapter implements ProviderAdapter {
  readonly providerId = 'jamendo';
  readonly displayName = 'Jamendo';
  readonly adapterVersion = '1.0.0';
  readonly priority = 110;

  get enabled(): boolean {
    return Boolean(
      process.env.JAMENDO_CLIENT_ID?.trim() &&
      process.env.JAMENDO_API_TERMS_ACCEPTED === 'true' &&
      process.env.JAMENDO_BREEZZE_APPROVED === 'true' &&
      process.env.JAMENDO_ENABLED !== 'false',
    );
  }

  readonly capabilities: ProviderCapabilities = {
    search: true,
    metadata: true,
    availability: true,
    // Full playback is resolved through Jamendo's documented stream endpoint
    // and only after the individual track's CC license is checked.
    playback: true,
    download: false,
    albums: true,
    artists: true,
    charts: true,
    genres: true,
  };

  private readonly baseUrl = (
    process.env.JAMENDO_API_URL ?? 'https://api.jamendo.com/v3.0'
  ).replace(/\/$/, '');

  constructor(private readonly cache: ProviderCacheService) {}

  private url(path: string, params: Record<string, string>): URL {
    const url = new URL(path.replace(/^\//, ''), `${this.baseUrl}/`);
    url.searchParams.set('client_id', process.env.JAMENDO_CLIENT_ID!.trim());
    url.searchParams.set('format', 'json');
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    return url;
  }

  private async request<T>(url: URL): Promise<T> {
    const response = await fetch(url, {
      headers: { accept: 'application/json', 'user-agent': 'Breezze/1.0 (+https://breezze.app)' },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`JAMENDO_HTTP_${response.status}`);
    const payload = await response.json() as T & JamendoEnvelope<unknown>;
    if (payload.headers?.status === 'failed' || (payload.headers?.code && payload.headers.code !== 0)) {
      throw new Error('JAMENDO_API_REJECTED_REQUEST');
    }
    return payload as T;
  }

  private mapTrack(track: JamendoTrack): ProviderTrack | null {
    if (!track.id || !track.name?.trim() || !track.artist_name?.trim()) return null;
    const duration = Number(track.duration);
    return {
      providerTrackId: String(track.id),
      title: track.name.trim(),
      artist: track.artist_name.trim(),
      artworkUrl: track.album_image || track.image || undefined,
      durationSec: Number.isFinite(duration) && duration > 0 ? duration : undefined,
      sourceUrl: this.safeTrackUrl(track.shareurl, String(track.id)),
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    if (!this.enabled) return providerUnsupported('JAMENDO_NOT_CONFIGURED');
    const key = `provider:jamendo:search:v1:${encodeURIComponent(q.toLowerCase())}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<JamendoEnvelope<JamendoTrack>>(
        this.url('/tracks/', { search: q, limit: '30', audioformat: 'mp32', include: 'licenses' }),
      );
      if (!Array.isArray(payload.results)) {
        return providerError('JAMENDO_INVALID_RESPONSE', 'Jamendo returned an invalid catalogue response', false);
      }
      const tracks = payload.results
        .map((track) => this.mapTrack(track))
        .filter((track): track is ProviderTrack => track !== null);
      const result = providerOk(tracks, 'Catalogue metadata provided by Jamendo');
      await this.cache.set(key, result, 120);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Jamendo request failed';
      return providerError('JAMENDO_SEARCH_FAILED', message, true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!/^\d{1,12}$/.test(providerTrackId)) {
      return providerError('INVALID_JAMENDO_TRACK_ID', 'Invalid Jamendo track identifier', false);
    }
    if (!this.enabled) return providerUnsupported('JAMENDO_NOT_CONFIGURED');
    const key = `provider:jamendo:track:v1:${providerTrackId}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<JamendoEnvelope<JamendoTrack>>(
        this.url('/tracks/', { id: providerTrackId, limit: '1', include: 'licenses' }),
      );
      const track = payload.results?.[0] ? this.mapTrack(payload.results[0]) : null;
      if (!track) return providerError('JAMENDO_TRACK_NOT_FOUND', 'Jamendo track metadata was not found', false);
      const result = providerOk(track, 'Catalogue metadata provided by Jamendo');
      await this.cache.set(key, result, 300);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Jamendo request failed';
      return providerError('JAMENDO_TRACK_FAILED', message, true);
    }
  }

  private safeTrackUrl(value: string | undefined, trackId: string): string {
    if (value) {
      try {
        const url = new URL(value);
        if (url.protocol === 'https:' && (url.hostname === 'jamendo.com' || url.hostname.endsWith('.jamendo.com'))) {
          return url.toString();
        }
      } catch {
        // Fall through to the canonical Jamendo track page.
      }
    }
    return `https://www.jamendo.com/track/${trackId}`;
  }

  private licenseAllowsStreaming(licenseUrl: string | undefined): boolean {
    if (!licenseUrl) return false;
    let license: URL;
    try {
      license = new URL(licenseUrl);
    } catch {
      return false;
    }
    if (license.protocol !== 'https:' || license.hostname !== 'creativecommons.org') return false;
    const path = license.pathname.toLowerCase();
    if (path.startsWith('/publicdomain/zero/')) return true;

    const commercial = [
      '/licenses/by/',
      '/licenses/by-sa/',
      '/licenses/by-nd/',
    ].some((prefix) => path.startsWith(prefix));
    if (commercial) return true;

    const nonCommercial = [
      '/licenses/by-nc/',
      '/licenses/by-nc-sa/',
      '/licenses/by-nc-nd/',
    ].some((prefix) => path.startsWith(prefix));
    return nonCommercial && process.env.BREEZZE_NONCOMMERCIAL === 'true';
  }

  async getAvailability(
    providerTrackId: string,
  ): Promise<ProviderResult<{ available: boolean }>> {
    if (!/^\d{1,12}$/.test(providerTrackId)) {
      return providerError('INVALID_JAMENDO_TRACK_ID', 'Invalid Jamendo track identifier', false);
    }
    if (!this.enabled) return providerUnsupported('JAMENDO_NOT_CONFIGURED');
    try {
      const payload = await this.request<JamendoEnvelope<JamendoTrack>>(
        this.url('/tracks/', { id: providerTrackId, limit: '1', include: 'licenses' }),
      );
      const track = payload.results?.[0];
      if (!track) return providerOk({ available: false });
      const allowed = this.licenseAllowsStreaming(track.license_ccurl);
      const attribution = allowed
        ? `“${track.name ?? 'Track'}” by ${track.artist_name ?? 'the artist'} — Jamendo; source: https://www.jamendo.com/track/${providerTrackId}; license: ${track.license_ccurl}`
        : undefined;
      return providerOk({ available: allowed }, attribution);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Jamendo availability check failed';
      return providerError('JAMENDO_AVAILABILITY_FAILED', message, true);
    }
  }

  async resolvePlayback(
    request: ProviderPlaybackRequest,
  ): Promise<ProviderResult<ProviderPlaybackSource>> {
    if (!/^\d{1,12}$/.test(request.providerTrackId)) {
      return providerError('INVALID_JAMENDO_TRACK_ID', 'Invalid Jamendo track identifier', false);
    }
    if (!this.enabled) return providerUnsupported('JAMENDO_NOT_CONFIGURED');

    try {
      // Jamendo documents /tracks/file with action=stream as its stream
      // resolver. Follow only a redirect to Jamendo-controlled HTTPS hosts.
      const endpoint = this.url('/tracks/file/', {
        id: request.providerTrackId,
        action: 'stream',
        audioformat: 'mp32',
      });
      const response = await fetch(endpoint, {
        redirect: 'manual',
        headers: { 'user-agent': 'Breezze/1.0 (+https://breezze.app)' },
        signal: AbortSignal.timeout(5000),
      });
      const location = response.headers.get('location');
      if (!response.ok && (response.status < 300 || response.status >= 400)) {
        return providerError('JAMENDO_STREAM_RESOLVE_FAILED', `Jamendo stream endpoint returned HTTP ${response.status}`, response.status >= 500);
      }
      if (!location) {
        return providerError('JAMENDO_STREAM_REDIRECT_MISSING', 'Jamendo did not return a stream redirect', true);
      }
      const streamUrl = new URL(location, endpoint);
      if (streamUrl.protocol !== 'https:' || !streamUrl.hostname.endsWith('.jamendo.com')) {
        return providerError('JAMENDO_STREAM_HOST_REJECTED', 'Jamendo returned an untrusted stream host', false);
      }
      return providerOk({
        url: streamUrl.toString(),
        expiresAt: new Date(Date.now() + 5 * 60 * 1000),
        mimeType: 'audio/mpeg',
        codec: 'mp3',
      }, request.authorization.attribution ?? 'Stream provided by Jamendo');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Jamendo stream resolution failed';
      return providerError('JAMENDO_PLAYBACK_FAILED', message, true);
    }
  }
}
