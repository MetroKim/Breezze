import { Injectable } from '@nestjs/common';
import * as crypto from 'node:crypto';
import {
  ProviderAdapter, ProviderCapabilities, ProviderTrack, ProviderPlaybackRequest,
  ProviderPlaybackSource,
} from './provider-adapter.interface';
import { ProviderCacheService } from './provider-cache.service';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

const spotifyTrackId = /^[A-Za-z0-9]{22}$/;

interface SpotifyTrack {
  id?: string;
  name?: string;
  duration_ms?: number;
  is_playable?: boolean;
  is_local?: boolean;
  artists?: Array<{ name?: string }>;
  album?: { images?: Array<{ url?: string }> };
}

interface SpotifySearchPayload {
  tracks?: { items?: SpotifyTrack[] };
}

interface SpotifyTokenPayload {
  access_token?: string;
  token_type?: string;
  expires_in?: number;
}

/**
 * Spotify music discovery through the official Web API.
 *
 * Spotify never supplies raw audio, download grants, or a native Breezze
 * audio-engine source. Users listen through the official Spotify application;
 * Premium is required for on-demand full-track playback.
 *
 * All client credentials and bearer tokens stay on this server, never on
 * Flutter or inside serialized provider results.
 */
@Injectable()
export class SpotifyAdapter implements ProviderAdapter {
  readonly providerId = 'spotify';
  readonly displayName = 'Spotify';
  readonly adapterVersion = '2026-11';
  readonly priority = 220;
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: false,
    playback: false, download: false, albums: true,
    artists: true, playlists: true,
  };

  private token: { accessToken: string; expiresAt: number } | null = null;
  private tokenRequest: Promise<string | null> | null = null;

  constructor(private readonly cache: ProviderCacheService) {}

  get enabled(): boolean {
    return process.env.SPOTIFY_ENABLED !== 'false' &&
      Boolean(process.env.SPOTIFY_CLIENT_ID?.trim() &&
              process.env.SPOTIFY_CLIENT_SECRET?.trim());
  }

  private async acquireToken(): Promise<string | null> {
    if (!this.enabled) return null;
    if (this.token && this.token.expiresAt > Date.now() + 30_000) {
      return this.token.accessToken;
    }
    if (this.tokenRequest) return this.tokenRequest;
    this.tokenRequest = (async () => {
      try {
        const identity = Buffer.from(
          process.env.SPOTIFY_CLIENT_ID!.trim() + ':' +
          process.env.SPOTIFY_CLIENT_SECRET!.trim(),
        ).toString('base64');
        const response = await fetch('https://accounts.spotify.com/api/token', {
          method: 'POST', redirect: 'error',
          headers: {
            Authorization: 'Basic ' + identity,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: 'grant_type=client_credentials',
          signal: AbortSignal.timeout(6000),
        });
        if (!response.ok) return null;
        const payload = await response.json() as SpotifyTokenPayload;
        if (payload.token_type?.toLowerCase() !== 'bearer' ||
            typeof payload.access_token !== 'string' ||
            !payload.access_token || !Number.isFinite(payload.expires_in) ||
            (payload.expires_in ?? 0) < 60) return null;
        const token = payload.access_token;
        this.token = {
          accessToken: token,
          expiresAt: Date.now() + Math.floor(payload.expires_in! * 1000),
        };
        return token;
      } catch {
        return null;
      }
    })().finally(() => { this.tokenRequest = null; });
    return this.tokenRequest;
  }

  private async request<T>(path: string, params?: URLSearchParams):
    Promise<ProviderResult<T>> {
    if (!this.enabled) return providerUnsupported('SPOTIFY_NOT_CONFIGURED');
    const token = await this.acquireToken();
    if (!token) {
      return providerError('SPOTIFY_AUTH_UNAVAILABLE',
        'Spotify API authorization is unavailable', true);
    }
    try {
      const url = new URL('https://api.spotify.com/v1/' + path);
      if (params) url.search = params.toString();
      const response = await fetch(url, {
        redirect: 'error',
        headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' },
        signal: AbortSignal.timeout(6500),
      });
      if (response.status === 401) this.token = null;
      if (response.status === 429) {
        return providerError('SPOTIFY_RATE_LIMITED',
          'Spotify API request quota reached', true);
      }
      if (!response.ok) {
        return providerError('SPOTIFY_API_UNAVAILABLE',
          'Spotify music catalog is unavailable', response.status >= 500 || response.status === 401);
      }
      return providerOk(await response.json() as T);
    } catch {
      return providerError('SPOTIFY_NETWORK_UNAVAILABLE',
        'Spotify music catalog cannot be reached', true);
    }
  }

  private mapTrack(row: SpotifyTrack): ProviderTrack | null {
    if (!spotifyTrackId.test(row.id ?? '') || !row.name?.trim() ||
        !row.artists?.[0]?.name?.trim() || row.is_local === true ||
        row.is_playable === false) return null;
    const id = row.id!;
    const image = row.album?.images?.find(i =>
      typeof i.url === 'string' && i.url.startsWith('https://'));
    return {
      providerTrackId: id,
      title: row.name.trim(),
      artist: row.artists[0].name!.trim(),
      durationSec: Number.isFinite(row.duration_ms) && (row.duration_ms ?? 0) > 0
        ? Math.floor(row.duration_ms! / 1000) : undefined,
      artworkUrl: image?.url,
      // A Spotify link is NOT a native audio stream.
      sourceUrl: 'https://open.spotify.com/track/' + id,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    if (!this.enabled) return providerUnsupported('SPOTIFY_NOT_CONFIGURED');
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const digest = crypto.createHash('sha256').update(q.toLowerCase()).digest('hex');
    const key = 'provider:spotify:search:v1:' + digest;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    const data = await this.request<SpotifySearchPayload>(
      'search', new URLSearchParams({ q, type: 'track', limit: '10' }),
    );
    if (data.kind !== 'ok') return data;
    if (!Array.isArray(data.value.tracks?.items)) {
      return providerError('SPOTIFY_INVALID_RESPONSE',
        'Spotify API returned an invalid search response');
    }
    const seen = new Set<string>();
    const result = providerOk(
      data.value.tracks.items
        .map(row => this.mapTrack(row))
        .filter((row): row is ProviderTrack =>
          row !== null && !seen.has(row.providerTrackId) &&
          (seen.add(row.providerTrackId), true)),
      'Spotify music catalog. Playback opens Spotify; not Breezze native audio.',
    );
    // Short-lived cache reduces Spotify development-mode API consumption.
    await this.cache.set(key, result, 90);
    return result;
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!spotifyTrackId.test(providerTrackId)) {
      return providerError('INVALID_SPOTIFY_TRACK_ID', 'Invalid Spotify track ID');
    }
    const result = await this.request<SpotifyTrack>('tracks/' + providerTrackId);
    if (result.kind !== 'ok') return result;
    const track = this.mapTrack(result.value);
    if (!track) return providerError('SPOTIFY_TRACK_UNAVAILABLE',
      'This track cannot be played in the current catalog');
    return providerOk(track, 'Spotify. Open the official Spotify app to listen.');
  }

  async getAvailability(): Promise<ProviderResult<{available: boolean}>> {
    return providerUnsupported('Spotify does not grant native third-party audio streams.');
  }

  async resolvePlayback(_request: ProviderPlaybackRequest):
    Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported('Spotify playback requires Spotify App Remote or Spotify Connect.');
  }
}
