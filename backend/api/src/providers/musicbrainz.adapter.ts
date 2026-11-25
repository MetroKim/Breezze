import { Injectable } from '@nestjs/common';
import * as crypto from 'node:crypto';
import {
  ProviderAdapter, ProviderCapabilities, ProviderTrack,
  ProviderPlaybackRequest, ProviderPlaybackSource,
} from './provider-adapter.interface';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';
import { ProviderCacheService } from './provider-cache.service';

type ArtistCredit = string | { name?: string; artist?: { name?: string } };
interface Recording {
  id?: string;
  title?: string;
  length?: number;
  'artist-credit'?: ArtistCredit[];
}
interface SearchResponse { recordings?: Recording[]; }

/**
 * Public MusicBrainz recording metadata fallback — never a Spotify mirror.
 *
 * Requires no developer key, but the free web service is limited to
 * non-commercial use and at most one request/second per client.
 * We reserve a global Redis permit (shared across API replicas) before each
 * outbound request, cache positive results, and fail closed if unavailable.
 */
@Injectable()
export class MusicBrainzAdapter implements ProviderAdapter {
  readonly providerId = 'musicbrainz';
  readonly displayName = 'MusicBrainz';
  readonly adapterVersion = '1.0.0';
  readonly priority = 70;
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: false,
    playback: false, download: false,
  };

  constructor(private readonly cache: ProviderCacheService) {}

  get enabled() {
    // Explicit acknowledgment avoids accidentally using the non-commercial
    // free endpoint for an unrestricted commercial production workload.
    return process.env.MUSICBRAINZ_NONCOMMERCIAL_ACK === 'true' &&
      process.env.MUSICBRAINZ_ENABLED !== 'false';
  }

  private static readonly recordingId =
    /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;

  private mapTrack(row: Recording): ProviderTrack | null {
    if (!MusicBrainzAdapter.recordingId.test(row.id ?? '') ||
        !row.title?.trim()) return null;
    const name = row['artist-credit']?.find(
      (credit): credit is Exclude<ArtistCredit, string> => typeof credit !== 'string',
    );
    const artist = name?.name?.trim() || name?.artist?.name?.trim();
    if (!artist) return null;
    return {
      providerTrackId: row.id!.toLowerCase(),
      title: row.title.trim(),
      artist,
      durationSec: typeof row.length === 'number' && row.length > 0
        ? Math.floor(row.length / 1000) : undefined,
      sourceUrl: 'https://musicbrainz.org/recording/' + row.id!.toLowerCase(),
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    if (!this.enabled) return providerUnsupported('MUSICBRAINZ_NOT_ENABLED');
    const normalized = query.trim().replace(/\s+/g, ' ');
    if (normalized.length < 2 || normalized.length > 120) return providerOk([]);
    const digest = crypto.createHash('sha256')
      .update(normalized.toLowerCase()).digest('hex');
    const key = 'provider:musicbrainz:search:v1:' + digest;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;

    // MusicBrainz requires strict 1 request/second. Avoid concurrent requests
    // or retries across all server replicas when no shared rate budget exists.
    if (!await this.cache.reserveProviderInterval('musicbrainz:recording', 1250)) {
      return providerUnsupported('MUSICBRAINZ_RATE_BUDGET_BUSY');
    }

    try {
      const url = new URL('https://musicbrainz.org/ws/2/recording/');
      url.searchParams.set('query', normalized);
      url.searchParams.set('fmt', 'json');
      url.searchParams.set('limit', '10');
      const response = await fetch(url, {
        redirect: 'error',
        headers: {
          Accept: 'application/json',
          'User-Agent': 'Breezze/1.0 (https://breezze.app)',
        },
        signal: AbortSignal.timeout(3500),
      });
      if (!response.ok) {
        return providerError('MUSICBRAINZ_UPSTREAM_UNAVAILABLE',
          'Metadata fallback currently unavailable',
          response.status === 429 || response.status >= 500);
      }
      const data = await response.json() as SearchResponse;
      if (!Array.isArray(data.recordings)) {
        return providerError('MUSICBRAINZ_BAD_RESPONSE',
          'Invalid metadata response');
      }
      const seen = new Set<string>();
      const tracks = data.recordings.map(recording => this.mapTrack(recording))
        .filter((track): track is ProviderTrack => track !== null)
        .filter(track => {
          if (seen.has(track.providerTrackId)) return false;
          seen.add(track.providerTrackId);
          return true;
        });
      const result = providerOk(tracks,
        'MusicBrainz recording metadata; no audio or playback entitlement');
      await this.cache.set(key, result, 3600);
      return result;
    } catch {
      return providerError('MUSICBRAINZ_NETWORK_UNAVAILABLE',
        'Metadata fallback timed out', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!MusicBrainzAdapter.recordingId.test(providerTrackId)) {
      return providerError('INVALID_MUSICBRAINZ_ID', 'Invalid recording ID');
    }
    if (!this.enabled) return providerUnsupported('MUSICBRAINZ_NOT_ENABLED');
    const key = 'provider:musicbrainz:recording:' + providerTrackId.toLowerCase();
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(key);
    if (cached) return cached;
    if (!await this.cache.reserveProviderInterval('musicbrainz:recording', 1250)) {
      return providerUnsupported('MUSICBRAINZ_RATE_BUDGET_BUSY');
    }
    try {
      const url = new URL('https://musicbrainz.org/ws/2/recording/' + providerTrackId);
      url.searchParams.set('fmt', 'json');
      const response = await fetch(url, {
        redirect: 'error',
        headers: {
          Accept: 'application/json',
          'User-Agent': 'Breezze/1.0 (https://breezze.app)',
        },
        signal: AbortSignal.timeout(3500),
      });
      if (!response.ok) return providerError('MUSICBRAINZ_UPSTREAM_UNAVAILABLE',
        'Metadata recording unavailable', response.status >= 500);
      const track = this.mapTrack(await response.json() as Recording);
      if (!track) return providerError('MUSICBRAINZ_TRACK_NOT_FOUND',
        'Recording metadata unavailable');
      const result = providerOk(track, 'Metadata from MusicBrainz');
      await this.cache.set(key, result, 3600);
      return result;
    } catch {
      return providerError('MUSICBRAINZ_NETWORK_UNAVAILABLE',
        'Recording lookup unavailable', true);
    }
  }

  async getAvailability(): Promise<ProviderResult<{ available: boolean }>> {
    return providerUnsupported('MusicBrainz supplies metadata, not audio rights.');
  }

  async resolvePlayback(_request: ProviderPlaybackRequest):
    Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported('MusicBrainz has no commercial audio stream.');
  }
}
