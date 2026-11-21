import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { ProviderRegistry } from '../providers/provider-registry.service';

@Injectable()
export class SearchService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly providers: ProviderRegistry,
  ) {}

  async search(query: string) {
    const q = query.trim();
    if (q.length < 2) {
      return { tracks: [], artists: [], albums: [], externalTracks: [], externalProviderStatus: 'skipped' };
    }

    const youtubeMusic = this.providers.get('youtube_music');
    const externalSearch = youtubeMusic?.capabilities.search
      ? youtubeMusic.search(q)
      : Promise.resolve({ kind: 'unsupported' as const, reason: 'YTMUSIC_SEARCH_NOT_CONFIGURED' });

    const [tracks, artists, albums, externalResult] = await Promise.all([this.prisma.track.findMany({
      where: { title: { contains: q, mode: 'insensitive' } },
      take: 20,
    }), this.prisma.artist.findMany({
      where: { name: { contains: q, mode: 'insensitive' } },
      take: 5,
    }), this.prisma.album.findMany({
      where: { title: { contains: q, mode: 'insensitive' } },
      take: 5,
    }), externalSearch]);

    return {
      tracks,
      artists,
      albums,
      externalTracks: externalResult.kind === 'ok' ? externalResult.value : [],
      externalProviderStatus: externalResult.kind,
    };
  }
}
