import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

export interface HomeSection {
  sectionType: 'recently_played' | 'favorites';
  title: string;
  layout: 'rail' | 'grid';
  trackIds: string[];
}

@Injectable()
export class HomeService {
  constructor(private readonly prisma: PrismaService) {}

  async feed(userId: string): Promise<HomeSection[]> {
    const [recent, favorites] = await Promise.all([
      this.prisma.recentlyPlayed.findMany({
        where: { userId },
        orderBy: { playedAt: 'desc' },
        take: 12,
        select: { trackId: true },
      }),
      this.prisma.favorite.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 12,
        select: { trackId: true },
      }),
    ]);

    const sections: HomeSection[] = [];

    if (recent.length > 0) {
      sections.push({
        sectionType: 'recently_played',
        title: 'Recently Played',
        layout: 'rail',
        trackIds: recent.map((r) => r.trackId),
      });
    }

    if (favorites.length > 0) {
      sections.push({
        sectionType: 'favorites',
        title: 'Your Favorites',
        layout: 'rail',
        trackIds: favorites.map((f) => f.trackId),
      });
    }

    return sections;
  }

  async recordPlay(userId: string, trackId: string, playedMs: number) {
    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { id: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');
    if (!Number.isInteger(playedMs) || playedMs < 30_000 || playedMs > 86_400_000) {
      throw new NotFoundException('PLAY_DURATION_NOT_QUALIFIED');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.recentlyPlayed.upsert({
        where: { userId_trackId: { userId, trackId } },
        create: { userId, trackId },
        update: { playedAt: new Date() },
      });
      await tx.listeningEvent.create({
        data: { userId, trackId, playedMs },
      });
    });
    return { recorded: true };
  }
}
