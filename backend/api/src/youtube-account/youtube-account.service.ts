import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import {
  createCipheriv, createDecipheriv, createHash, randomBytes,
} from 'node:crypto';
import { PrismaService } from '../prisma.service';

const YOUTUBE_READONLY = 'https://www.googleapis.com/auth/youtube.readonly';
const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const REVOKE_ENDPOINT = 'https://oauth2.googleapis.com/revoke';
const CHANNEL_ENDPOINT =
  'https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true&maxResults=1';
const PLAYLIST_ENDPOINT =
  'https://www.googleapis.com/youtube/v3/playlists?part=snippet%2CcontentDetails&mine=true&maxResults=25';
const PLAYLIST_ID = /^[A-Za-z0-9_-]{10,128}$/;
const CHANNEL_ID = /^UC[A-Za-z0-9_-]{22}$/;

interface ConnectionConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  key: Buffer;
}

function digest(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

/** Owner-bound AES-256-GCM: a copied token row cannot be decrypted as a different user. */
function sealToken(value: string, userId: string, key: Buffer): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(Buffer.from('breezze:youtube-account:v1:' + userId));
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), ciphertext]
    .map((part) => part.toString('base64url')).join('.');
}

function unsealToken(value: string, userId: string, key: Buffer): string {
  const pieces = value.split('.');
  if (pieces.length !== 3) throw new ServiceUnavailableException('YOUTUBE_TOKEN_INVALID');
  const [iv, tag, data] = pieces.map((item) => Buffer.from(item, 'base64url'));
  if (iv.length !== 12 || tag.length !== 16 || data.length === 0) {
    throw new ServiceUnavailableException('YOUTUBE_TOKEN_INVALID');
  }
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAAD(Buffer.from('breezze:youtube-account:v1:' + userId));
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
  } catch {
    throw new ServiceUnavailableException('YOUTUBE_TOKEN_INVALID');
  }
}

type GoogleToken = {
  access_token?: unknown;
  refresh_token?: unknown;
  expires_in?: unknown;
  scope?: unknown;
  token_type?: unknown;
};

@Injectable()
export class YoutubeAccountService {
  constructor(private readonly prisma: PrismaService) {}

  private config(): ConnectionConfig {
    if (process.env.YOUTUBE_ACCOUNT_LINK_ENABLED !== 'true') {
      throw new ServiceUnavailableException('YOUTUBE_ACCOUNT_LINK_DISABLED');
    }
    const clientId = process.env.YOUTUBE_ACCOUNT_CLIENT_ID ?? '';
    const clientSecret = process.env.YOUTUBE_ACCOUNT_CLIENT_SECRET ?? '';
    const redirectUri = process.env.YOUTUBE_ACCOUNT_REDIRECT_URI ?? '';
    const key = Buffer.from(process.env.YOUTUBE_ACCOUNT_TOKEN_KEY ?? '', 'base64');
    if (!clientId || !clientSecret || !redirectUri || key.length !== 32) {
      throw new ServiceUnavailableException('YOUTUBE_ACCOUNT_LINK_NOT_CONFIGURED');
    }
    let callback: URL;
    try { callback = new URL(redirectUri); }
    catch { throw new ServiceUnavailableException('YOUTUBE_ACCOUNT_REDIRECT_INVALID'); }
    if (callback.protocol !== 'https:' ||
        callback.username || callback.password || callback.search || callback.hash ||
        !callback.pathname.endsWith('/api/v1/youtube-account/callback')) {
      throw new ServiceUnavailableException('YOUTUBE_ACCOUNT_REDIRECT_INVALID');
    }
    return { clientId, clientSecret, redirectUri, key };
  }

  async status(userId: string) {
    const configured = process.env.YOUTUBE_ACCOUNT_LINK_ENABLED === 'true' &&
      Boolean(process.env.YOUTUBE_ACCOUNT_CLIENT_ID &&
        process.env.YOUTUBE_ACCOUNT_CLIENT_SECRET &&
        process.env.YOUTUBE_ACCOUNT_REDIRECT_URI &&
        Buffer.from(process.env.YOUTUBE_ACCOUNT_TOKEN_KEY ?? '', 'base64').length === 32);
    const record = await this.prisma.youtubeAccountConnection.findUnique({
      where: { userId },
      select: { channelTitle: true, channelId: true, createdAt: true },
    });
    return {
      available: configured,
      connected: Boolean(record),
      ...(record ? {
        channelTitle: record.channelTitle,
        channelId: record.channelId,
        connectedAt: record.createdAt,
      } : {}),
      provider: 'youtube_data_api',
      // The official YouTube Data API playlists endpoint is NOT a complete
      // representation of the private YouTube Music library.
      scope: 'read_only_youtube_playlists',
    };
  }

  async start(userId: string) {
    const cfg = this.config();
    const state = randomBytes(32).toString('base64url');
    const verifier = randomBytes(48).toString('base64url');
    const flow = await this.prisma.youtubeAccountLinkFlow.create({
      data: {
        userId,
        stateHash: digest(state),
        codeVerifier: verifier,
        expiresAt: new Date(Date.now() + 10 * 60_000),
      },
      select: { id: true, expiresAt: true },
    });
    const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    url.searchParams.set('client_id', cfg.clientId);
    url.searchParams.set('redirect_uri', cfg.redirectUri);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('scope', YOUTUBE_READONLY);
    url.searchParams.set('access_type', 'offline');
    url.searchParams.set('prompt', 'consent');
    url.searchParams.set('state', state);
    url.searchParams.set('code_challenge',
      createHash('sha256').update(verifier).digest('base64url'));
    url.searchParams.set('code_challenge_method', 'S256');
    return { authorizationUrl: url.toString(), expiresAt: flow.expiresAt };
  }

  private async exchangeCode(code: string, verifier: string, cfg: ConnectionConfig) {
    const response = await fetch(TOKEN_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: cfg.clientId,
        client_secret: cfg.clientSecret,
        redirect_uri: cfg.redirectUri,
        code_verifier: verifier,
        grant_type: 'authorization_code',
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new UnauthorizedException('YOUTUBE_ACCOUNT_CODE_REJECTED');
    const payload = await response.json() as GoogleToken;
    const scope = String(payload.scope ?? '').split(' ');
    if (typeof payload.access_token !== 'string' ||
        typeof payload.refresh_token !== 'string' ||
        payload.access_token.length < 20 || payload.refresh_token.length < 20 ||
        payload.token_type !== 'Bearer' ||
        !scope.includes(YOUTUBE_READONLY) ||
        typeof payload.expires_in !== 'number' ||
        payload.expires_in < 60 || payload.expires_in > 86_400) {
      throw new UnauthorizedException('YOUTUBE_ACCOUNT_SCOPE_OR_REFRESH_MISSING');
    }
    return {
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token,
      expiresAt: new Date(Date.now() + payload.expires_in * 1000),
    };
  }

  private async getOwnChannel(accessToken: string) {
    const response = await fetch(CHANNEL_ENDPOINT, {
      headers: { Authorization: 'Bearer ' + accessToken },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new UnauthorizedException('YOUTUBE_CHANNEL_UNAVAILABLE');
    const data = await response.json() as {
      items?: Array<{ id?: unknown; snippet?: { title?: unknown } }>;
    };
    const first = Array.isArray(data.items) ? data.items[0] : undefined;
    if (!first || typeof first.id !== 'string' || !CHANNEL_ID.test(first.id)) {
      throw new UnauthorizedException('YOUTUBE_CHANNEL_NOT_FOUND');
    }
    return {
      channelId: first.id,
      channelTitle: typeof first.snippet?.title === 'string'
        ? first.snippet.title.trim().slice(0, 150) : null,
    };
  }

  /**
   * Browser callback never receives Breezze JWTs. The random state is
   * hashed at rest and binds the Google consent to an authenticated starter.
   */
  async callback(state: string, code?: string, providerError?: string): Promise<boolean> {
    if (typeof state !== 'string' || state.length < 32 || state.length > 256) return false;
    const flow = await this.prisma.youtubeAccountLinkFlow.findUnique({
      where: { stateHash: digest(state) },
    });
    if (!flow || flow.status !== 'pending' || flow.expiresAt.getTime() <= Date.now()) {
      return false;
    }
    const claimed = await this.prisma.youtubeAccountLinkFlow.updateMany({
      where: { id: flow.id, status: 'pending', expiresAt: { gt: new Date() } },
      data: { status: 'processing' },
    });
    if (claimed.count !== 1) return false;
    if (providerError || typeof code !== 'string' || code.length < 8 || code.length > 2048) {
      await this.failFlow(flow.id);
      return false;
    }
    try {
      const cfg = this.config();
      const token = await this.exchangeCode(code, flow.codeVerifier, cfg);
      const channel = await this.getOwnChannel(token.accessToken);
      const existing = await this.prisma.youtubeAccountConnection.findUnique({
        where: { channelId: channel.channelId },
        select: { userId: true },
      });
      if (existing && existing.userId !== flow.userId) {
        throw new ConflictException('YOUTUBE_ACCOUNT_ALREADY_LINKED');
      }
      // Atomically claim the finishing flow and store encrypted tokens.
      // A concurrent disconnect cancels pending/processing flows.
      await this.prisma.$transaction(async (tx) => {
        const finished = await tx.youtubeAccountLinkFlow.updateMany({
          where: { id: flow.id, status: 'processing' },
          data: { status: 'completed', completedAt: new Date() },
        });
        if (finished.count !== 1) {
          throw new ConflictException('YOUTUBE_ACCOUNT_FLOW_CANCELLED');
        }
        await tx.youtubeAccountConnection.upsert({
          where: { userId: flow.userId },
          create: {
            userId: flow.userId,
            channelId: channel.channelId,
            channelTitle: channel.channelTitle,
            accessTokenCiphertext: sealToken(token.accessToken, flow.userId, cfg.key),
            refreshTokenCiphertext: sealToken(token.refreshToken, flow.userId, cfg.key),
            accessExpiresAt: token.expiresAt,
          },
          update: {
            channelId: channel.channelId,
            channelTitle: channel.channelTitle,
            accessTokenCiphertext: sealToken(token.accessToken, flow.userId, cfg.key),
            refreshTokenCiphertext: sealToken(token.refreshToken, flow.userId, cfg.key),
            accessExpiresAt: token.expiresAt,
          },
        });
      });
      return true;
    } catch {
      await this.failFlow(flow.id);
      return false;
    }
  }

  private async failFlow(flowId: string) {
    await this.prisma.youtubeAccountLinkFlow.updateMany({
      where: { id: flowId, status: 'processing' },
      data: { status: 'failed', completedAt: new Date() },
    });
  }

  private async refreshedToken(userId: string) {
    const cfg = this.config();
    const record = await this.prisma.youtubeAccountConnection.findUnique({
      where: { userId },
    });
    if (!record) throw new NotFoundException('YOUTUBE_ACCOUNT_NOT_CONNECTED');
    if (record.accessExpiresAt.getTime() > Date.now() + 90_000) {
      return unsealToken(record.accessTokenCiphertext, userId, cfg.key);
    }
    const refreshToken = unsealToken(record.refreshTokenCiphertext, userId, cfg.key);
    const response = await fetch(TOKEN_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
        client_id: cfg.clientId,
        client_secret: cfg.clientSecret,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new UnauthorizedException('YOUTUBE_ACCOUNT_RECONNECT_REQUIRED');
    const payload = await response.json() as GoogleToken;
    if (typeof payload.access_token !== 'string' ||
        payload.token_type !== 'Bearer' ||
        typeof payload.expires_in !== 'number' ||
        payload.expires_in < 60 || payload.expires_in > 86_400) {
      throw new ServiceUnavailableException('YOUTUBE_ACCOUNT_REFRESH_INVALID');
    }
    // updateMany conditional: a logout/account-switch deleting the row
    // cannot re-create an OAuth connection from an in-flight refresh.
    const updated = await this.prisma.youtubeAccountConnection.updateMany({
      where: { userId, refreshTokenCiphertext: record.refreshTokenCiphertext },
      data: {
        accessTokenCiphertext: sealToken(payload.access_token, userId, cfg.key),
        accessExpiresAt: new Date(Date.now() + payload.expires_in * 1000),
        ...(typeof payload.refresh_token === 'string' && payload.refresh_token.length >= 20
          ? { refreshTokenCiphertext: sealToken(payload.refresh_token, userId, cfg.key) } : {}),
      },
    });
    if (updated.count !== 1) throw new UnauthorizedException('YOUTUBE_ACCOUNT_RECONNECT_REQUIRED');
    return payload.access_token;
  }

  async playlists(userId: string) {
    const access = await this.refreshedToken(userId);
    const response = await fetch(PLAYLIST_ENDPOINT, {
      headers: { Authorization: 'Bearer ' + access },
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 401 || response.status === 403) {
      throw new UnauthorizedException('YOUTUBE_ACCOUNT_RECONNECT_REQUIRED');
    }
    if (!response.ok) {
      throw new ServiceUnavailableException('YOUTUBE_PLAYLISTS_UPSTREAM_UNAVAILABLE');
    }
    const data = await response.json() as {
      nextPageToken?: unknown;
      items?: Array<{
        id?: unknown;
        snippet?: {
          title?: unknown;
          thumbnails?: { default?: { url?: unknown } };
        };
        contentDetails?: { itemCount?: unknown };
      }>;
    };
    const items = Array.isArray(data.items) ? data.items.slice(0, 25) : [];
    return {
      source: 'youtube_data_api',
      scope: 'read_only_youtube_playlists',
      items: items.flatMap((item) => {
        const id = item.id;
        if (typeof id !== 'string' || !PLAYLIST_ID.test(id)) return [];
        const title = item.snippet?.title;
        const artwork = item.snippet?.thumbnails?.default?.url;
        const sanitizedArtwork = this.safeYouTubeArtwork(artwork);
        return [{
          playlistId: id,
          title: typeof title === 'string' ? title.slice(0, 200) : 'YouTube playlist',
          artworkUrl: sanitizedArtwork,
          trackCount: Number.isSafeInteger(item.contentDetails?.itemCount)
            ? item.contentDetails?.itemCount : null,
        }];
      }),
      hasMore: typeof data.nextPageToken === 'string' && data.nextPageToken.length > 0,
      // No nextPageToken is returned until cursor authentication and paging
      // are implemented. Never claim to return a complete YouTube Music library.
    };
  }

  async playlistItems(userId: string, playlistId: string) {
    if (!PLAYLIST_ID.test(playlistId)) {
      throw new BadRequestException('YOUTUBE_PLAYLIST_ID_INVALID');
    }
    // The playlist must belong to the same YouTube channel that the Breezze
    // listener explicitly connected; the caller never supplies a channelId.
    const connection = await this.prisma.youtubeAccountConnection.findUnique({
      where: { userId },
      select: { channelId: true },
    });
    if (!connection) throw new NotFoundException('YOUTUBE_ACCOUNT_NOT_CONNECTED');
    const access = await this.refreshedToken(userId);
    const playlistUrl = new URL('https://www.googleapis.com/youtube/v3/playlists');
    playlistUrl.searchParams.set('part', 'snippet');
    playlistUrl.searchParams.set('id', playlistId);
    playlistUrl.searchParams.set('maxResults', '1');
    const ownerResponse = await fetch(playlistUrl, {
      headers: { Authorization: 'Bearer ' + access },
      signal: AbortSignal.timeout(10_000),
    });
    if (!ownerResponse.ok) {
      throw new ServiceUnavailableException('YOUTUBE_PLAYLIST_LOOKUP_UNAVAILABLE');
    }
    const ownerData = await ownerResponse.json() as {
      items?: Array<{ snippet?: { channelId?: unknown } }>;
    };
    if (!Array.isArray(ownerData.items) ||
        ownerData.items[0]?.snippet?.channelId !== connection.channelId) {
      throw new NotFoundException('YOUTUBE_PLAYLIST_NOT_OWNED');
    }
    const itemUrl = new URL('https://www.googleapis.com/youtube/v3/playlistItems');
    itemUrl.searchParams.set('part', 'snippet,contentDetails');
    itemUrl.searchParams.set('playlistId', playlistId);
    itemUrl.searchParams.set('maxResults', '50');
    const response = await fetch(itemUrl, {
      headers: { Authorization: 'Bearer ' + access },
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 401 || response.status === 403) {
      throw new UnauthorizedException('YOUTUBE_ACCOUNT_RECONNECT_REQUIRED');
    }
    if (!response.ok) {
      throw new ServiceUnavailableException('YOUTUBE_PLAYLIST_ITEMS_UNAVAILABLE');
    }
    const data = await response.json() as {
      nextPageToken?: unknown;
      items?: Array<{
        snippet?: {
          title?: unknown;
          videoOwnerChannelTitle?: unknown;
          thumbnails?: { default?: { url?: unknown } };
          resourceId?: { videoId?: unknown };
        };
        contentDetails?: { videoId?: unknown };
      }>;
    };
    const videoId = /^[A-Za-z0-9_-]{11}$/;
    const items = Array.isArray(data.items) ? data.items.slice(0, 50) : [];
    return {
      source: 'youtube_data_api',
      playlistId,
      items: items.flatMap((item) => {
        const id = item.contentDetails?.videoId ??
          item.snippet?.resourceId?.videoId;
        if (typeof id !== 'string' || !videoId.test(id)) return [];
        const title = item.snippet?.title;
        const artist = item.snippet?.videoOwnerChannelTitle;
        return [{
          videoId: id,
          title: typeof title === 'string'
            ? title.slice(0, 200) : 'YouTube video',
          artist: typeof artist === 'string' && artist.trim()
            ? artist.slice(0, 120) : 'YouTube',
          artworkUrl: this.safeYouTubeArtwork(item.snippet?.thumbnails?.default?.url),
          playback: 'visible_youtube_only',
        }];
      }),
      hasMore: typeof data.nextPageToken === 'string' &&
        data.nextPageToken.length > 0,
    };
  }

  private safeYouTubeArtwork(raw: unknown): string | null {
    if (typeof raw !== 'string') return null;
    try {
      const url = new URL(raw);
      const host = url.hostname.toLowerCase();
      if (url.protocol !== 'https:' || url.username || url.password) return null;
      if (!(
        host === 'ytimg.com' || host.endsWith('.ytimg.com') ||
        host === 'ggpht.com' || host.endsWith('.ggpht.com') ||
        host === 'googleusercontent.com' || host.endsWith('.googleusercontent.com')
      )) return null;
      return url.toString();
    } catch {
      return null;
    }
  }

  async disconnect(userId: string) {
    // Data deletion must work even if Google credentials were disabled or
    // rotated after the listener linked their account.
    const record = await this.prisma.youtubeAccountConnection.findUnique({
      where: { userId },
      select: { refreshTokenCiphertext: true },
    });
    await this.prisma.$transaction(async (tx) => {
      await tx.youtubeAccountLinkFlow.updateMany({
        where: { userId, status: { in: ['pending', 'processing'] } },
        data: { status: 'cancelled', completedAt: new Date() },
      });
      await tx.youtubeAccountConnection.deleteMany({ where: { userId } });
    });
    if (record) {
      // Google revocation is best-effort; local token deletion is mandatory
      // even when Google is offline or revocation fails.
      try {
        const cfg = this.config();
        const token = unsealToken(record.refreshTokenCiphertext, userId, cfg.key);
        await fetch(REVOKE_ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ token }),
          signal: AbortSignal.timeout(5_000),
        });
      } catch { /* Already locally disconnected; no credentials in logs. */ }
    }
    return { disconnected: true };
  }
}
