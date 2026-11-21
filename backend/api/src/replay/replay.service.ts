import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

export interface ReplaySummary {
  totalPlays: number;
  topSongIds: { id: string; title: string; artist: string; plays: number }[];
  topArtistIds: { id: string; name: string; plays: number }[];
}

@Injectable()
export class ReplayService {
  constructor(private readonly prisma: PrismaService) {}

  async summary(userId: string): Promise<ReplaySummary> {
    const events = await this.prisma.listeningEvent.findMany({
      where: { userId },
      select: { trackId: true },
    });

    const songCounts = new Map<string, number>();
    for (const e of events) {
      songCounts.set(e.trackId, (songCounts.get(e.trackId) ?? 0) + 1);
    }

    const trackIds = [...songCounts.keys()];
    const tracks = trackIds.length
      ? await this.prisma.track.findMany({
          where: { id: { in: trackIds } },
          select: { id: true, title: true, artist: { select: { id: true, name: true } } },
        })
    : [];

    const artistCounts = new Map<string, number>();
    for (const t of tracks) {
      const plays = songCounts.get(t.id) ?? 0;
      artistCounts.set(t.artist.id, (artistCounts.get(t.artist.id) ?? 0) + plays);
    }

    const topSongIds = [...songCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([id, plays]) => {
        const track = tracks.find((item) => item.id === id);
        return {
          id,
          title: track?.title ?? 'Unknown track',
          artist: track?.artist.name ?? 'Unknown artist',
          plays,
        };
      });

    const topArtistIds = [...artistCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([id, plays]) => ({
        id,
        name: tracks.find((item) => item.artist.id === id)?.artist.name ?? 'Unknown artist',
        plays,
      }));

    return {
      totalPlays: events.length,
      topSongIds,
      topArtistIds,
    };
  }
}
