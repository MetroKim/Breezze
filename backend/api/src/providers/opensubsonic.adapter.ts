import { createHmac, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';
import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter, ProviderCapabilities, ProviderPlaybackRequest,
  ProviderPlaybackSource, ProviderTrack,
} from './provider-adapter.interface';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

/**
 * Opt-in full-song bridge for a Breezze-operated/partner-authorized
 * OpenSubsonic library. This DOES NOT supply recordings or distribution rights.
 *
 * Never forward an upstream API key or source URL to Flutter. The signed URL
 * points only to Breezze's own restricted audio relay, whose GET rechecks
 * the authenticated owner's per-track rights and territory.
 */
const SONG_ID = /^[a-zA-Z0-9_-]{1,128}$/;
const MIME = /^audio\/(mpeg|mp3|mp4|aac|flac|x-flac|ogg|opus|wav|x-wav)(?:\s*;.*)?$/i;
const RELAY_LEASE_MS = 30 * 60_000;
const UUID = /^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i;

export interface OpenSubsonicGrant {
  id: string;
  canonicalTrackId: string;
  userId: string;
  territory: string;
  expires: number;
}

interface OpenSubsonicConfig {
  upstream: string;
  publicApi: string;
  apiKey: string;
  signingKey: string;
}

export function safeOpenSubsonicOrigin(raw: string): string | null {
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    if (url.protocol !== 'https:' || !host || isIP(host) ||
        host === 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || host.endsWith('.internal') ||
        url.username || url.password || url.search || url.hash ||
        url.pathname !== '/' || url.port && url.port !== '443') return null;
    return url.origin;
  } catch {
    return null;
  }
}

@Injectable()
export class OpenSubsonicAdapter implements ProviderAdapter {
  readonly providerId = 'opensubsonic';
  readonly displayName = 'Breezze Authorized Audio Library (OpenSubsonic)';
  readonly adapterVersion = '8.4.0';
  readonly priority = 80;
  readonly capabilities: ProviderCapabilities = {
    // Do not expose private partner song metadata via the generic public
    // /providers/:id/tracks/:trackId route. Approved catalog rows live in
    // Breezze's existing canonical catalog and account-safe lookup.
    search: false, metadata: false, availability: true,
    playback: true, download: false,
  };

  private config(): OpenSubsonicConfig | null {
    const env = process.env;
    if (env.OPEN_SUBSONIC_ENABLED !== 'true') return null;
    const upstream = safeOpenSubsonicOrigin(env.OPEN_SUBSONIC_ORIGIN ?? '');
    const publicApi = safeOpenSubsonicOrigin(env.BREEZZE_PUBLIC_API_ORIGIN ?? '');
    const apiKey = env.OPEN_SUBSONIC_API_KEY ?? '';
    const signingKey = env.OPEN_SUBSONIC_RELAY_SIGNING_KEY ?? '';
    if (!upstream || !publicApi || apiKey.length < 16 ||
        signingKey.length < 32 || upstream === publicApi) return null;
    return { upstream, publicApi, apiKey, signingKey };
  }

  get enabled(): boolean { return this.config() !== null; }

  private upstreamUrl(operation: 'getSong' | 'stream', id: string, config: OpenSubsonicConfig): URL {
    const url = new URL('/rest/' + operation + '.view', config.upstream);
    url.searchParams.set('id', id);
    url.searchParams.set('apiKey', config.apiKey);
    url.searchParams.set('v', '1.16.1');
    url.searchParams.set('c', 'breezze-v8');
    url.searchParams.set('f', 'json');
    return url;
  }

  private async upstreamSong(id: string): Promise<{ track: ProviderTrack; mimeType: string } | null> {
    const config = this.config();
    if (!config || !SONG_ID.test(id)) return null;
    try {
      const response = await fetch(this.upstreamUrl('getSong', id, config), {
        headers: { accept: 'application/json' },
        redirect: 'error',
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok || Number(response.headers.get('content-length') ?? '0') > 64_000) return null;
      const result = await response.json() as {
        'subsonic-response'?: {
          status?: string;
          song?: { id?: string; title?: string; artist?: string; duration?: number;
            contentType?: string; isVideo?: boolean; };
        };
      };
      const envelope = result?.['subsonic-response'];
      const song = envelope?.song;
      if (envelope?.status !== 'ok' || song?.id !== id ||
          song.isVideo === true || !song.title?.trim() ||
          !song.artist?.trim() || !Number.isFinite(song.duration) ||
          (song.duration ?? 0) <= 0 ||
          !MIME.test(song.contentType ?? '')) return null;
      return {
        track: {
          providerTrackId: id, title: song.title.trim(),
          artist: song.artist.trim(), durationSec: song.duration,
        },
        mimeType: (song.contentType ?? '').split(';', 1)[0].toLowerCase(),
      };
    } catch {
      return null;
    }
  }

  async search(_query: string): Promise<ProviderResult<ProviderTrack[]>> {
    // Public search is deliberately disabled: server catalog existence alone
    // does not prove each work is licensed to all Breezze listeners.
    return providerUnsupported('OPEN_SUBSONIC_CURATED_CATALOG_ONLY');
  }

  async getTrack(_id: string): Promise<ProviderResult<ProviderTrack>> {
    return providerUnsupported('OPEN_SUBSONIC_METADATA_PRIVATE');
  }

  async getAvailability(id: string, _territory: string): Promise<ProviderResult<{ available: boolean }>> {
    if (!this.enabled) return providerUnsupported('OPEN_SUBSONIC_NOT_CONFIGURED');
    return providerOk({ available: (await this.upstreamSong(id)) !== null });
  }

  issueGrant(payload: OpenSubsonicGrant): string | null {
    const config = this.config();
    if (!config || !SONG_ID.test(payload.id) || !UUID.test(payload.canonicalTrackId) ||
        !payload.userId || !/^[A-Z]{2}$/.test(payload.territory) ||
        !Number.isSafeInteger(payload.expires) || payload.expires <= Date.now() ||
        payload.expires > Date.now() + RELAY_LEASE_MS + 1000) return null;
    const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const mac = createHmac('sha256', config.signingKey).update(encoded).digest('base64url');
    return encoded + '.' + mac;
  }

  verifyGrant(token: string, id: string): OpenSubsonicGrant | null {
    const config = this.config();
    if (!config || !SONG_ID.test(id) || typeof token !== 'string' ||
        token.length > 1300 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) return null;
    const [encoded, supplied] = token.split('.');
    const expected = createHmac('sha256', config.signingKey)
      .update(encoded).digest();
    let provided: Buffer;
    try { provided = Buffer.from(supplied, 'base64url'); } catch { return null; }
    if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) return null;
    try {
      const raw = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8')) as OpenSubsonicGrant;
      if (raw.id !== id || !UUID.test(raw.canonicalTrackId) ||
          typeof raw.userId !== 'string' || !raw.userId ||
          typeof raw.territory !== 'string' || !/^[A-Z]{2}$/.test(raw.territory) ||
          !Number.isSafeInteger(raw.expires) || raw.expires <= Date.now() ||
          raw.expires > Date.now() + RELAY_LEASE_MS + 1000) return null;
      return raw;
    } catch {
      return null;
    }
  }

  async resolvePlayback(request: ProviderPlaybackRequest): Promise<ProviderResult<ProviderPlaybackSource>> {
    const config = this.config();
    if (!config) return providerUnsupported('OPEN_SUBSONIC_NOT_CONFIGURED');
    if (request.authorization.action !== 'stream.full' ||
        !request.userId || !request.canonicalTrackId ||
        !UUID.test(request.canonicalTrackId) || !SONG_ID.test(request.providerTrackId) ||
        !/^[A-Z]{2}$/.test(request.territory)) {
      return providerUnsupported('OPEN_SUBSONIC_AUTHORIZATION_REQUIRED');
    }
    const song = await this.upstreamSong(request.providerTrackId);
    if (!song) return providerError('OPEN_SUBSONIC_AUDIO_MISSING', 'No playable full audio returned', true);
    const expiryMs = Math.min(
      Date.now() + RELAY_LEASE_MS,
      request.authorization.expiresAt?.getTime() ?? Number.MAX_SAFE_INTEGER,
    );
    if (expiryMs <= Date.now() + 15_000) {
      return providerUnsupported('OPEN_SUBSONIC_RIGHTS_EXPIRED');
    }
    const expiresAt = new Date(expiryMs);
    const token = this.issueGrant({
      id: request.providerTrackId,
      canonicalTrackId: request.canonicalTrackId,
      userId: request.userId,
      territory: request.territory,
      expires: expiryMs,
    });
    if (!token) return providerUnsupported('OPEN_SUBSONIC_GRANT_INVALID');
    const url = new URL('/api/v1/providers/opensubsonic/audio/' +
      encodeURIComponent(request.providerTrackId), config.publicApi);
    url.searchParams.set('grant', token);
    return providerOk({
      url: url.toString(), expiresAt,
      // The source is already checked as audio via getSong.
      // The relay independently validates upstream content-type per request.
      mimeType: song.mimeType,
      codec: song.mimeType === 'audio/flac' || song.mimeType === 'audio/x-flac'
        ? 'flac' : song.mimeType === 'audio/mp4' ? 'aac'
        : song.mimeType === 'audio/ogg' || song.mimeType === 'audio/opus' ? 'opus'
        : song.mimeType.includes('wav') ? 'wav' : 'mp3',
    });
  }

  async fetchAuthorizedBytes(id: string, range?: string): Promise<Response | null> {
    const config = this.config();
    if (!config || !SONG_ID.test(id) ||
        (range != null && !/^bytes=\d+-\d*$/.test(range))) return null;
    const headers: Record<string, string> = { accept: 'audio/*', 'accept-encoding': 'identity' };
    if (range) headers.range = range;
    const abort = new AbortController();
    // Deadline covers only response headers. A song body can last hours.
    const timer = setTimeout(() => abort.abort(), 15_000);
    try {
      return await fetch(this.upstreamUrl('stream', id, config), {
        headers, redirect: 'error', signal: abort.signal,
      });
    } catch { return null; }
    finally { clearTimeout(timer); }
  }

  static validMediaResponse(response: Response, requestedRange: boolean): boolean {
    if (!(response.status === 200 || response.status === 206)) return false;
    if (requestedRange && response.status !== 206) return false;
    if (!MIME.test(response.headers.get('content-type') ?? '')) return false;
    const size = response.headers.get('content-length');
    if (size != null && (!/^\d+$/.test(size) || Number(size) <= 0)) return false;
    if (response.status === 206 && !/^bytes \d+-\d+\/(\d+|\*)$/.test(
      response.headers.get('content-range') ?? '')) return false;
    return response.body !== null;
  }
}
