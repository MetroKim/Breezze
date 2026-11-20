import { Injectable, NotFoundException } from '@nestjs/common';
import { YoutubeMetadataAdapter } from '../providers/youtube-metadata.adapter';

export interface BzVideo {
  id: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  durationSec?: number;
  viewCount?: number;
  embeddable: boolean;
  embedUrl: string;
}

@Injectable()
export class VideoService {
  constructor(private readonly youtube: YoutubeMetadataAdapter) {}

  /** GET /video/search?q= — keyless video metadata search. Free for
   *  every signed-in user; playback is via the provider's official
   *  embed player, which is the sanctioned free mechanism. */
  async search(query: string): Promise<BzVideo[]> {
    const q = query.trim();
    if (q.length < 2) return [];
    const result = await this.youtube.searchVideos(q);
    if (result.kind !== 'ok') return [];
    return result.value
      .filter((v) => v.embeddable)
      .map((v) => ({
        id: v.providerVideoId,
        title: v.title,
        artist: v.artist,
        artworkUrl: v.artworkUrl,
        durationSec: v.durationSec,
        viewCount: v.viewCount,
        embeddable: v.embeddable,
        embedUrl: `https://www.youtube.com/embed/${v.providerVideoId}`,
      }));
  }

  /** Single video by provider id — used by the detail screen. */
  async get(videoId: string): Promise<BzVideo> {
    const result = await this.youtube.searchVideos(videoId);
    if (result.kind === 'ok') {
      const hit = result.value.find((v) => v.providerVideoId === videoId);
      if (hit) {
        return {
          id: hit.providerVideoId,
          title: hit.title,
          artist: hit.artist,
          artworkUrl: hit.artworkUrl,
          durationSec: hit.durationSec,
          viewCount: hit.viewCount,
          embeddable: hit.embeddable,
          embedUrl: `https://www.youtube.com/embed/${hit.providerVideoId}`,
        };
      }
    }
    throw new NotFoundException('VIDEO_NOT_FOUND');
  }
}
