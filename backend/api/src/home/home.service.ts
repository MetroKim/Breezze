import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RecommendationsService } from '../recommendations/recommendations.service';

export interface HomeSection {
  sectionType: 'personalized' | 'recently_played' | 'favorites';
  title: string;
  layout: 'rail' | 'grid';
  trackIds: string[];
}

@Injectable()
export class HomeService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly recommendations: RecommendationsService,
  ) {}

  async feed(userId: string): Promise<HomeSection[]> {
    const [recent, favorites, recommendations] = await Promise.all([
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
      this.recommendations.forUser(userId),
    ]);

    const sections: HomeSection[] = [];

    if (recommendations.length > 0) {
      sections.push({
        sectionType: 'personalized',
        title: 'Made for You',
        layout: 'rail',
        trackIds: recommendations.map((item) => item.trackId),
      });
    }

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

  async recordPlay(userId: string, eventId: string, trackId: string, playedMs: number) {
    if (!Number.isInteger(playedMs) || playedMs < 30_000 || playedMs > 86_400_000) {
      throw new BadRequestException('PLAY_DURATION_NOT_QUALIFIED');
    }

    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { id: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');

    const existing = await this.prisma.listeningEvent.findUnique({
      where: { id: eventId },
      select: { userId: true, trackId: true, playedMs: true },
    });
    if (existing) {
      if (existing.userId !== userId || existing.trackId !== trackId || existing.playedMs !== playedMs) {
        throw new ConflictException('PLAY_EVENT_ID_CONFLICT');
      }
      return { recorded: true, duplicate: true };
    }

    try {
      await this.prisma.$transaction(async (tx) => {
        // The durable event ID is inserted first; history updates only once.
        await tx.listeningEvent.create({
          data: { id: eventId, userId, trackId, playedMs },
        });
        await tx.recentlyPlayed.upsert({
          where: { userId_trackId: { userId, trackId } },
          create: { userId, trackId },
          update: { playedAt: new Date() },
        });
      });
    } catch (error) {
      // Concurrent retries can both pass the preflight read. The PK decides
      // the winner; accept only an exact match to the persisted event.
      if (error && typeof error === 'object' && 'code' in error && error.code === 'P2002') {
        const raced = await this.prisma.listeningEvent.findUnique({
          where: { id: eventId },
          select: { userId: true, trackId: true, playedMs: true },
        });
        if (raced?.userId === userId && raced.trackId === trackId && raced.playedMs === playedMs) {
          return { recorded: true, duplicate: true };
        }
        throw new ConflictException('PLAY_EVENT_ID_CONFLICT');
      }
      throw error;
    }

    return { recorded: true, duplicate: false };
  }
}
