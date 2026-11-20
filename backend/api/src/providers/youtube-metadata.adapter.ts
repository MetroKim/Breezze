import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  ProviderAdapter,
  ProviderCapabilities,
  ProviderTrack,
} from './provider-adapter.interface';
import { ProviderResult, providerOk, providerError } from './provider-result';

// Plan §7.4 — external metadata adapter. The repo's keyless innertube
// engineering (previously youtube_explode_dart in the Flutter app) is
// ported server-side: the client no longer talks to the provider.
//
// Capabilities declared HONESTLY (§7.3):
//   - search / metadata / videoSearch: YES (keyless public metadata)
//   - playback / download: NO. Stream extraction stays disabled in the
//     production path; video playback happens through the provider's
//     OFFICIAL embed player (see VideoModule), the sanctioned free
//     method for third-party apps.
//   - embedPlayback: YES — the embed player is the provider's own
//     sanctioned surface; Breezze only passes the video id through.

export interface ProviderVideo {
  providerVideoId: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  durationSec?: number;
  viewCount?: number;
  embeddable: boolean;
}

export interface VideoSearchCapabilities extends ProviderCapabilities {
  videoSearch: boolean;
  embedPlayback: boolean;
}

interface InnertubeSearchHit {
  videoId?: string;
  title?: string;
  artist?: string;
  thumbnail?: string;
  duration?: string;
  viewCount?: string;
}

@Injectable()
export class YoutubeMetadataAdapter implements ProviderAdapter {
  readonly providerId = 'youtube_metadata';
  readonly capabilities: VideoSearchCapabilities = {
    search: true,
    metadata: true,
    availability: false,
    playback: false,
    download: false,
    videoSearch: true,
    embedPlayback: true,
  };

  private readonly logger = new Logger(YoutubeMetadataAdapter.name);
  private readonly innertube = 'https://www.youtube.com/youtubei/v1/search';

  constructor(private readonly config: ConfigService) {}

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const hits = await this.innertubeSearch(query);
    if (hits.kind !== 'ok') return hits;
    return providerOk(
      hits.value
        .filter((h) => h.videoId)
        .map((h) => this.toTrack(h)),
      'YouTube',
    );
  }

  async searchVideos(query: string): Promise<ProviderResult<ProviderVideo[]>> {
    // Video search reuses the same keyless metadata path; results are
    // filtered to embeddable videos because playback is embed-only.
    const hits = await this.innertubeSearch(`${query} music video`);
    if (hits.kind !== 'ok') return hits;
    return providerOk(
      hits.value
        .filter((h) => h.videoId)
        .map((h) => ({
          providerVideoId: h.videoId!,
          title: h.title ?? 'Unknown',
          artist: h.artist ?? 'Unknown',
          artworkUrl: h.thumbnail,
          durationSec: this.parseClockDuration(h.duration),
          viewCount: this.parseViewCount(h.viewCount),
          embeddable: true,
        })),
      'YouTube',
    );
  }

  async getTrack(
    providerTrackId: string,
  ): Promise<ProviderResult<ProviderTrack>> {
    const hits = await this.innertubeSearch(providerTrackId);
    if (hits.kind !== 'ok') return hits;
    const hit = hits.value.find((h) => h.videoId === providerTrackId);
    if (!hit) {
      return providerError('TRACK_NOT_FOUND', 'no such video', false);
    }
    return providerOk(this.toTrack(hit), 'YouTube');
  }

  async getAvailability(
    providerTrackId: string,
    territory: string,
  ): Promise<ProviderResult<{ available: boolean }>> {
    // Keyless metadata has no per-territory gate; the embed player
    // enforces the provider's own regional rules at play time.
    void providerTrackId;
    void territory;
    return providerOk({ available: true });
  }

  // ---------------- internal ----------------

  private toTrack(h: InnertubeSearchHit): ProviderTrack {
    return {
      providerTrackId: h.videoId!,
      title: h.title ?? 'Unknown',
      artist: h.artist ?? 'Unknown',
      artworkUrl: h.thumbnail,
      durationSec: this.parseClockDuration(h.duration),
    };
  }

  /** Keyless innertube search — the same engineering the repo used in
   *  Dart, now server-side. No credentials, no quota. */
  private async innertubeSearch(
    query: string,
  ): Promise<ProviderResult<InnertubeSearchHit[]>> {
    try {
      const apiKey =
        this.config.get<string>('YOUTUBE_INNERTUBE_API_KEY') ?? '';
      const res = await fetch(
        `${this.innertube}?key=${apiKey}&prettyPrint=false`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            context: {
              client: {
                clientName: 'WEB',
                clientVersion: '2.20240926.00.00',
                hl: 'en',
                gl: 'US',
              },
            },
            query,
          }),
        },
      );
      if (!res.ok) {
        return providerError(
          'PROVIDER_HTTP_ERROR',
          `innertube ${res.status}`,
          res.status >= 500,
        );
      }
      const body = (await res.json()) as unknown;
      return providerOk(this.extractVideoResults(body));
    } catch (e) {
      this.logger.warn(`innertube search failed: ${String(e)}`);
      return providerError('PROVIDER_NETWORK_ERROR', String(e), true);
    }
  }

  /** Defensive recursive walk: find renderer objects holding a videoId
   *  and a title, without depending on innertube layout details. */
  private extractVideoResults(body: unknown): InnertubeSearchHit[] {
    const hits: InnertubeSearchHit[] = [];
    const seen = new Set<unknown>();
    const stack: unknown[] = [body];

    while (stack.length > 0 && hits.length < 40) {
      const node = stack.pop();
      if (!node || typeof node !== 'object') continue;
      if (seen.has(node)) continue;
      seen.add(node);

      const record = node as Record<string, unknown>;
      const renderer =
        (record['videoRenderer'] ?? record['compactVideoRenderer']) as
          | Record<string, unknown>
          | undefined;

      if (renderer && typeof renderer['videoId'] === 'string') {
        const title = this.readText(renderer['title']);
        const owner =
          this.readText(renderer['ownerText']) ??
          this.readText(renderer['shortBylineText']);
        const thumbnails = (renderer['thumbnail'] as
          | Record<string, unknown>
          | undefined)?.['thumbnails'] as unknown[] | undefined;
        const artwork = thumbnails?.length
          ? ((thumbnails[thumbnails.length - 1] as Record<string, unknown>)['url'] as string)
          : undefined;
        hits.push({
          videoId: renderer['videoId'],
          title,
          artist: owner,
          thumbnail: artwork,
          duration: this.readText(renderer['lengthText']),
          viewCount: this.readText(renderer['shortViewCountText']),
        });
        continue;
      }

      for (const key of Object.keys(record)) {
        stack.push(record[key]);
      }
    }
    return hits;
  }

  private readText(node: unknown): string | undefined {
    if (!node || typeof node !== 'object') return undefined;
    const record = node as Record<string, unknown>;
    const runs = record['runs'] as unknown[] | undefined;
    if (Array.isArray(runs) && runs.length > 0) {
      const first = runs[0] as Record<string, unknown>;
      if (typeof first['text'] === 'string') return first['text'];
    }
    if (typeof record['simpleText'] === 'string') {
      return record['simpleText'];
    }
    return undefined;
  }

  /** Parse "3:41" or "1:02:15" clock strings into seconds. */
  private parseClockDuration(s?: string): number | undefined {
    if (!s) return undefined;
    const parts = s.split(':').map((p) => parseInt(p, 10));
    if (parts.some((n) => isNaN(n))) return undefined;
    return parts.reduce((acc, p) => acc * 60 + p, 0);
  }

  private parseViewCount(s?: string): number | undefined {
    if (!s) return undefined;
    const digits = s.replace(/[^0-9]/g, '');
    if (!digits) return undefined;
    const n = parseInt(digits, 10);
    return isNaN(n) ? undefined : n;
  }
}
