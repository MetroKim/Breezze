import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { RecommendationsService } from './recommendations.service';

describe('RecommendationsService', () => {
  const prisma = {
    userPreference: { findUnique: jest.fn() },
    recentlyPlayed: { findMany: jest.fn() },
    favorite: { findMany: jest.fn() },
    listeningEvent: { groupBy: jest.fn() },
    track: { findMany: jest.fn() },
  };
  const rights = { filterFullStream: jest.fn() };
  let service: RecommendationsService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.userPreference.findUnique.mockResolvedValue({ country: 'TZ' });
    prisma.recentlyPlayed.findMany.mockResolvedValue([]);
    prisma.favorite.findMany.mockResolvedValue([]);
    prisma.listeningEvent.groupBy.mockResolvedValue([
      { trackId: 'listened-a', _count: { trackId: 5 } },
      { trackId: 'listened-b', _count: { trackId: 3 } },
    ]);
    prisma.track.findMany.mockImplementation(({ where }: any) => {
      if (where.id?.in) {
        return Promise.resolve([
          { id: 'listened-a', artistId: 'artist-a' },
          { id: 'listened-b', artistId: 'artist-b' },
        ]);
      }
      if (where.artistId === 'artist-a') {
        return Promise.resolve([
          { id: 'a-1', artistId: 'artist-a' },
          { id: 'a-2', artistId: 'artist-a' },
          { id: 'a-3', artistId: 'artist-a' },
        ]);
      }
      if (where.artistId === 'artist-b') {
        return Promise.resolve([{ id: 'b-1', artistId: 'artist-b' }]);
      }
      return Promise.resolve([]);
    });
    rights.filterFullStream.mockImplementation((ids: string[]) => Promise.resolve(new Set(ids)));
    service = new RecommendationsService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
    );
  });

  it('returns no playback recommendations until the user has a valid territory', async () => {
    prisma.userPreference.findUnique.mockResolvedValue({ country: null });

    await expect(service.forUser('user-1')).resolves.toEqual([]);
    expect(prisma.listeningEvent.groupBy).not.toHaveBeenCalled();
    expect(rights.filterFullStream).not.toHaveBeenCalled();
  });

  it('ranks listening artists, caps each artist at two tracks, and checks full-play rights', async () => {
    rights.filterFullStream.mockResolvedValue(new Set(['a-3', 'b-1']));

    await expect(service.forUser('user-1')).resolves.toEqual([
      { trackId: 'b-1', reason: 'Because you listen to this artist' },
      { trackId: 'a-3', reason: 'Because you listen to this artist' },
    ]);

    expect(rights.filterFullStream).toHaveBeenCalledWith(
      ['a-1', 'b-1', 'a-2', 'a-3'],
      'TZ',
    );
  });

  it('interleaves artist candidates so one prolific artist cannot starve the others', async () => {
    prisma.track.findMany.mockImplementation(({ where }: any) => {
      if (where.id?.in) {
        return Promise.resolve([
          { id: 'listened-a', artistId: 'artist-a' },
          { id: 'listened-b', artistId: 'artist-b' },
        ]);
      }
      if (where.artistId === 'artist-a') {
        return Promise.resolve([
          { id: 'a-1', artistId: 'artist-a' },
          { id: 'a-2', artistId: 'artist-a' },
          { id: 'a-3', artistId: 'artist-a' },
        ]);
      }
      return Promise.resolve([
        { id: 'b-1', artistId: 'artist-b' },
        { id: 'b-2', artistId: 'artist-b' },
      ]);
    });
    rights.filterFullStream.mockResolvedValue(new Set(['a-1', 'a-2', 'a-3', 'b-1', 'b-2']));

    const result = await service.forUser('user-1');

    expect(result.slice(0, 3).map((item) => item.trackId)).toEqual(['a-1', 'b-1', 'a-2']);
    expect(result.filter((item) => item.trackId.startsWith('a-'))).toHaveLength(2);
  });

  it('excludes recently played and favorited tracks before checking candidates', async () => {
    prisma.recentlyPlayed.findMany.mockResolvedValue([{ trackId: 'recent-1' }]);
    prisma.favorite.findMany.mockResolvedValue([{ trackId: 'favorite-1' }]);

    await service.forUser('user-1');

    const candidateQueries = prisma.track.findMany.mock.calls.slice(1).map(([query]) => query);
    expect(candidateQueries.length).toBeGreaterThan(0);
    for (const candidateQuery of candidateQueries) {
      expect(candidateQuery.where.id.notIn).toEqual(
        expect.arrayContaining(['recent-1', 'favorite-1']),
      );
    }
  });

  it('uses rights-filtered popular tracks for a new listener', async () => {
    prisma.listeningEvent.groupBy
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        { trackId: 'popular-1', _count: { trackId: 20 } },
        { trackId: 'popular-2', _count: { trackId: 15 } },
      ]);
    prisma.track.findMany.mockResolvedValue([
      { id: 'popular-1', artistId: 'artist-a' },
      { id: 'popular-2', artistId: 'artist-b' },
    ]);

    await expect(service.forUser('new-user')).resolves.toEqual([
      { trackId: 'popular-1', reason: 'Popular on Breezze' },
      { trackId: 'popular-2', reason: 'Popular on Breezze' },
    ]);
    expect(rights.filterFullStream).toHaveBeenCalledWith(['popular-1', 'popular-2'], 'TZ');
  });
});
