import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { YoutubeMetadataAdapter } from '../providers/youtube-metadata.adapter';

export interface ExternalTrackDto {
  providerTrackId: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  durationSec?: number;
  source: string;
}

@Injectable()
export class SearchService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly youtube: YoutubeMetadataAdapter,
  ) {}

  async search(query: string) {
    const q = query.trim();
    if (q.length < 2) {
      return { tracks: [], artists: [], albums: [] };
    }

    const tracks = await this.prisma.track.findMany({
      where: { title: { contains: q, mode: 'insensitive' } },
      take: 20,
    });

    const artists = await this.prisma.artist.findMany({
      where: { name: { contains: q, mode: 'insensitive' } },
      take: 5,
    });

    const albums = await this.prisma.album.findMany({
      where: { title: { contains: q, mode: 'insensitive' } },
      take: 5,
    });

    return { tracks, artists, albums };
  }

  /** Aggregated external search: the keyless provider metadata path,
   *  now server-side (plan §7). The Flutter app calls this instead of
   *  talking to the provider itself. Honest empty result on provider
   *  failure — never a fake list. */
  async searchExternal(query: string): Promise<ExternalTrackDto[]> {
    const q = query.trim();
    if (q.length < 2) return [];
    const result = await this.youtube.search(q);
    if (result.kind === 'ok') {
      return result.value.map((t) => ({
        providerTrackId: t.providerTrackId,
        title: t.title,
        artist: t.artist,
        artworkUrl: t.artworkUrl,
        durationSec: t.durationSec,
        source: this.youtube.providerId,
      }));
    }
    return [];
  }
}
