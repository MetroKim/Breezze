import { Injectable, Optional } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { ProviderCacheService } from './provider-cache.service';
import { ProviderTrack } from './provider-adapter.interface';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const MAX_RESULTS = 25;

interface SearchItem {
  id?: { videoId?: string };
  snippet?: {
    title?: string;
    channelTitle?: string;
    thumbnails?: { high?: { url?: string }; medium?: { url?: string } };
    liveBroadcastContent?: string;
  };
}

interface YoutubeSearchEnvelope {
  items?: SearchItem[];
}

interface YoutubeVideoEnvelope {
  items?: Array<{
    id?: string;
    snippet?: SearchItem['snippet'];
    status?: { embeddable?: boolean; privacyStatus?: string };
  }>;
}

/**
 * Official YouTube Data API (public-video discovery only).
 *
 * The key is loaded exclusively from a server environment variable; never put
 * it in Flutter, git, a diagnostics response or a provider URL sent to users.
 * The Data API cannot provide audio-only streams, media download grants or
 * YouTube Music subscriptions.
 */
@Injectable()
export class OfficialYouTubeDataService {
  constructor(@Optional() private readonly cache?: ProviderCacheService) {}
  get configured(): boolean {
    // A key pasted into a conversation must be rotated/restricted before use.
    // Do not accidentally activate it when a staged Railway variable is
    // promoted with a backend deployment. Production is opt-in explicitly.
    if (process.env.NODE_ENV === 'production' &&
        process.env.YOUTUBE_DATA_API_ENABLED !== 'true') return false;
    return Boolean((process.env.YOUTUBE_DATA_API_KEY ?? '').trim());
  }

  private get key(): string {
    return (process.env.YOUTUBE_DATA_API_KEY ?? '').trim();
  }

  private requestUrl(endpoint: 'search' | 'videos'): URL {
    const url = new URL('https://www.googleapis.com/youtube/v3/' + endpoint);
    url.searchParams.set('key', this.key);
    return url;
  }

  private async request<T>(url: URL): Promise<ProviderResult<T>> {
    try {
      // Google documents the YouTube Data API key query parameter. This URL
      // must never enter logs, exceptions, caches, analytics or error messages.
      const response = await fetch(url, {
        headers: { accept: 'application/json' },
        redirect: 'error',
        signal: AbortSignal.timeout(6500),
      });
      if (!response.ok) {
        // Do not forward Google's error payload: it could contain credentials.
        return providerError('YOUTUBE_DATA_UPSTREAM_REJECTED',
          'Official YouTube metadata is temporarily unavailable',
          response.status === 429 || response.status >= 500);
      }
      return providerOk(await response.json() as T);
    } catch {
      return providerError('YOUTUBE_DATA_NETWORK_UNAVAILABLE',
        'Official YouTube metadata is temporarily unavailable', true);
    }
  }

  async searchMusicVideos(query: string, limit = 20):
    Promise<ProviderResult<ProviderTrack[]>> {
    if (!this.configured) return providerUnsupported('YOUTUBE_DATA_KEY_NOT_CONFIGURED');
    const q = query.trim();
    if (q.length < 2 || q.length > 120 ||
        !Number.isInteger(limit) || limit < 1 || limit > MAX_RESULTS) {
      return providerError('INVALID_YOUTUBE_VIDEO_SEARCH', 'Invalid video search input');
    }
    // Search has its own 100-calls/day Google quota as of 2026. Cache each
    // query across replicas and preserve a reserved margin for other clients.
    const queryKey = createHash('sha256').update(q.toLowerCase()).digest('hex');
    const cacheKey = 'provider:youtube:official-search:v1:' + queryKey + ':' + limit;
    const cached = await this.cache?.get<ProviderResult<ProviderTrack[]>>(cacheKey);
    if (cached) return cached;
    if (this.cache && !await this.cache.reserveDailyProviderRequest(
      'youtube-search', 80,
    )) return providerUnsupported('YOUTUBE_SEARCH_DAILY_BUDGET_EXHAUSTED');

    const url = this.requestUrl('search');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('type', 'video');
    url.searchParams.set('videoCategoryId', '10');
    url.searchParams.set('videoEmbeddable', 'true');
    url.searchParams.set('videoSyndicated', 'true');
    url.searchParams.set('safeSearch', 'moderate');
    url.searchParams.set('maxResults', String(limit));
    url.searchParams.set('q', q);

    const result = await this.request<YoutubeSearchEnvelope>(url);
    if (result.kind !== 'ok') return result;
    if (!Array.isArray(result.value.items)) {
      return providerError('YOUTUBE_DATA_INVALID_RESPONSE', 'Invalid YouTube video search response');
    }
    const seen = new Set<string>();
    const tracks: ProviderTrack[] = [];
    for (const item of result.value.items) {
      const id = item.id?.videoId ?? '';
      const title = item.snippet?.title?.trim() ?? '';
      const channel = item.snippet?.channelTitle?.trim() ?? '';
      if (!VIDEO_ID.test(id) || !title || !channel || seen.has(id) ||
          item.snippet?.liveBroadcastContent === 'live') continue;
      seen.add(id);
      const artworkUrl = item.snippet?.thumbnails?.high?.url ??
        item.snippet?.thumbnails?.medium?.url;
      tracks.push({
        providerTrackId: id,
        title,
        artist: channel,
        // This is a visible official YouTube watch URL, NOT an audio source.
        sourceUrl: 'https://www.youtube.com/watch?v=' + id,
        artworkUrl: artworkUrl?.startsWith('https://') ? artworkUrl : undefined,
      });
    }
    const ready = providerOk(tracks,
      'Official YouTube Data API music videos; open only in visible official YouTube player');
    await this.cache?.set(cacheKey, ready, 15 * 60);
    return ready;
  }

  async getVideo(videoId: string): Promise<ProviderResult<{
    videoId: string;
    title: string;
    channel: string;
    embeddable: boolean;
    watchUrl: string;
    playbackAvailable: false;
  }>> {
    if (!VIDEO_ID.test(videoId)) {
      return providerError('INVALID_YOUTUBE_VIDEO_ID', 'Invalid video ID');
    }
    if (!this.configured) return providerUnsupported('YOUTUBE_DATA_KEY_NOT_CONFIGURED');
    const cacheKey = 'provider:youtube:official-video:v1:' + videoId;
    const cached = await this.cache?.get<ProviderResult<{
      videoId: string; title: string; channel: string; embeddable: boolean;
      watchUrl: string; playbackAvailable: false;
    }>>(cacheKey);
    if (cached) return cached;
    const url = this.requestUrl('videos');
    url.searchParams.set('part', 'snippet,status');
    url.searchParams.set('id', videoId);
    const result = await this.request<YoutubeVideoEnvelope>(url);
    if (result.kind !== 'ok') return result;
    const video = result.value.items?.find(item => item.id === videoId);
    if (!video || typeof video.snippet?.title !== 'string') {
      return providerError('YOUTUBE_VIDEO_NOT_FOUND', 'YouTube video not available');
    }
    const ready = providerOk({
      videoId,
      title: video.snippet.title,
      channel: video.snippet.channelTitle ?? '',
      embeddable: video.status?.embeddable === true && video.status?.privacyStatus === 'public',
      watchUrl: 'https://www.youtube.com/watch?v=' + videoId,
      playbackAvailable: false as const,
    }, 'Official YouTube metadata; never a native audio playback entitlement');
    await this.cache?.set(cacheKey, ready, 60 * 60);
    return ready;
  }
}
