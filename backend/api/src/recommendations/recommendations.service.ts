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

  async forUser(userId: string, edgeTerritory?: string): Promise<RecommendationItem[]> {
    const territory = edgeTerritory?.trim().toUpperCase();
    // Rights-sensitive recommendations use only the trusted edge country,
    // never the editable country preference stored in the user's profile.
    if (!territory || !/^[A-Z]{2}$/.test(territory)) return [];

    const [recent, favorites, listening] = await Promise.all([
      this.prisma.recentlyPlayed.findMany({
        where: { userId, isServerVerified: true },
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

    // Fetch a bounded candidate window per artist. A single globally ordered
    // LIMIT can be monopolized by one prolific artist and starve every other
    // artist before rights filtering or the two-per-artist diversity cap.
    const candidatesByArtist = await Promise.all(artistIds.map((artistId) =>
      this.prisma.track.findMany({
        where: {
          artistId,
          id: { notIn: [...excludedIds] },
        },
        orderBy: { title: 'asc' },
        take: 12,
        select: { id: true, artistId: true },
      }),
    ));

    const rankedCandidates: CandidateTrack[] = [];
    const maxCandidates = Math.max(0, ...candidatesByArtist.map((items) => items.length));
    for (let index = 0; index < maxCandidates; index += 1) {
      for (const artistCandidates of candidatesByArtist) {
        const candidate = artistCandidates[index];
        if (candidate) rankedCandidates.push(candidate);
      }
    }

    return this.selectPlayable(rankedCandidates, territory, () =>
      'Because you listen to this artist',
    );
  }

  private async popularFallback(
    territory: string,
    excludedIds: Set<string>,
  ): Promise<RecommendationItem[]> {
    const popular = await this.prisma.listeningEvent.groupBy({
      by: ['trackId'],
      where: { isServerVerified: true },
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
    const playableIds = await this.rights.filterFullStream(
      candidates.map((track) => track.id),
      territory,
    );

    for (const track of candidates) {
      if (selected.length >= 12) break;
      if (!playableIds.has(track.id)) continue;
      const count = artistCounts.get(track.artistId) ?? 0;
      if (count >= 2) continue;
      artistCounts.set(track.artistId, count + 1);
      selected.push({ trackId: track.id, reason: reasonFor(track) });
    }
    return selected;
  }
}
