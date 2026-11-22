import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';

export interface RecommendationItem {
  trackId: string;
  reason: string;
}

interface CandidateTrack {
  id: string;
  artistId: string;
}

@Injectable()
export class RecommendationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
  ) {}

  async forUser(userId: string): Promise<RecommendationItem[]> {
    const preference = await this.prisma.userPreference.findUnique({
      where: { userId },
      select: { country: true },
    });
    const territory = preference?.country?.trim().toUpperCase();
    // A recommendation must never imply playback availability in an
    // unknown territory. Ask the user to set a country before personalizing.
    if (!territory || !/^[A-Z]{2}$/.test(territory)) return [];

    const [recent, favorites, listening] = await Promise.all([
      this.prisma.recentlyPlayed.findMany({
        where: { userId },
        orderBy: { playedAt: 'desc' },
        take: 50,
        select: { trackId: true },
      }),
      this.prisma.favorite.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 100,
        select: { trackId: true },
      }),
      this.prisma.listeningEvent.groupBy({
        by: ['trackId'],
        where: { userId },
        _count: { trackId: true },
        orderBy: { _count: { trackId: 'desc' } },
        take: 100,
      }),
    ]);

    const excludedIds = new Set([
      ...recent.map((item) => item.trackId),
      ...favorites.map((item) => item.trackId),
    ]);

    if (listening.length === 0) {
      return this.popularFallback(territory, excludedIds);
    }

    const listenedTrackIds = listening.map((item) => item.trackId);
    const listenedTracks = await this.prisma.track.findMany({
      where: { id: { in: listenedTrackIds } },
      select: { id: true, artistId: true },
    });
    const artistByTrack = new Map(listenedTracks.map((track) => [track.id, track.artistId]));
    const artistCounts = new Map<string, number>();
    for (const event of listening) {
      const artistId = artistByTrack.get(event.trackId);
      if (artistId) {
        artistCounts.set(artistId, (artistCounts.get(artistId) ?? 0) + event._count.trackId);
      }
    }
    const artistIds = [...artistCounts.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 5)
      .map(([artistId]) => artistId);

    if (artistIds.length === 0) {
      return this.popularFallback(territory, excludedIds);
    }

    const candidates = await this.prisma.track.findMany({
      where: {
        artistId: { in: artistIds },
        id: { notIn: [...excludedIds] },
      },
      orderBy: [{ artistId: 'asc' }, { title: 'asc' }],
      take: 60,
      select: { id: true, artistId: true },
    });

    const byArtist = new Map(candidates.map((track) => [track.artistId, [] as CandidateTrack[]]));
    for (const candidate of candidates) {
      byArtist.get(candidate.artistId)?.push(candidate);
    }
    const rankedCandidates = artistIds.flatMap((artistId) => byArtist.get(artistId) ?? []);
    return this.selectPlayable(rankedCandidates, territory, (track) =>
      'Because you listen to this artist',
    );
  }

  private async popularFallback(
    territory: string,
    excludedIds: Set<string>,
  ): Promise<RecommendationItem[]> {
    const popular = await this.prisma.listeningEvent.groupBy({
      by: ['trackId'],
      _count: { trackId: true },
      orderBy: { _count: { trackId: 'desc' } },
      take: 60,
    });
    const ids = popular
      .map((item) => item.trackId)
      .filter((id) => !excludedIds.has(id));
    if (ids.length === 0) return [];

    const tracks = await this.prisma.track.findMany({
      where: { id: { in: ids } },
      select: { id: true, artistId: true },
    });
    const byId = new Map(tracks.map((track) => [track.id, track]));
    const ranked = ids.map((id) => byId.get(id)).filter((track): track is CandidateTrack => Boolean(track));
    return this.selectPlayable(ranked, territory, () => 'Popular on Breezze');
  }

  private async selectPlayable(
    candidates: CandidateTrack[],
    territory: string,
    reasonFor: (track: CandidateTrack) => string,
  ): Promise<RecommendationItem[]> {
    const selected: RecommendationItem[] = [];
    const artistCounts = new Map<string, number>();

    // Bound concurrent rights checks so a large candidate pool cannot fan
    // out an unbounded burst of database queries.
    for (let offset = 0; offset < candidates.length && selected.length < 12; offset += 5) {
      const batch = candidates.slice(offset, offset + 5);
      const decisions = await Promise.all(batch.map((track) =>
        this.rights.decide({
          userId: null,
          trackId: track.id,
          action: 'stream.full',
          territory,
        }),
      ));

      for (let index = 0; index < batch.length && selected.length < 12; index += 1) {
        const track = batch[index];
        const decision = decisions[index];
        if (!decision.allowed || decision.previewOnly) continue;
        const count = artistCounts.get(track.artistId) ?? 0;
        if (count >= 2) continue;
        artistCounts.set(track.artistId, count + 1);
        selected.push({ trackId: track.id, reason: reasonFor(track) });
      }
    }
    return selected;
  }
}
