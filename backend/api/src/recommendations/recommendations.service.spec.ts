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
  const rights = { decide: jest.fn() };
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
      return Promise.resolve([
        { id: 'a-1', artistId: 'artist-a' },
        { id: 'a-2', artistId: 'artist-a' },
        { id: 'a-3', artistId: 'artist-a' },
        { id: 'b-1', artistId: 'artist-b' },
      ]);
    });
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
    });
    service = new RecommendationsService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
    );
  });

  it('returns no playback recommendations until the user has a valid territory', async () => {
    prisma.userPreference.findUnique.mockResolvedValue({ country: null });

    await expect(service.forUser('user-1')).resolves.toEqual([]);
    expect(prisma.listeningEvent.groupBy).not.toHaveBeenCalled();
    expect(rights.decide).not.toHaveBeenCalled();
  });

  it('ranks listening artists, caps each artist at two tracks, and checks full-play rights', async () => {
    rights.decide.mockImplementation(({ trackId }: { trackId: string }) =>
      Promise.resolve({
        allowed: trackId !== 'a-1',
        previewOnly: trackId === 'a-2',
      }),
    );

    await expect(service.forUser('user-1')).resolves.toEqual([
      { trackId: 'a-3', reason: 'Because you listen to this artist' },
      { trackId: 'b-1', reason: 'Because you listen to this artist' },
    ]);

    expect(rights.decide).toHaveBeenCalledWith({
      userId: null,
      trackId: 'a-1',
      action: 'stream.full',
      territory: 'TZ',
    });
  });

  it('excludes recently played and favorited tracks before checking candidates', async () => {
    prisma.recentlyPlayed.findMany.mockResolvedValue([{ trackId: 'recent-1' }]);
    prisma.favorite.findMany.mockResolvedValue([{ trackId: 'favorite-1' }]);

    await service.forUser('user-1');

    const candidateQuery = prisma.track.findMany.mock.calls[1][0];
    expect(candidateQuery.where.id.notIn).toEqual(
      expect.arrayContaining(['recent-1', 'favorite-1']),
    );
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
    expect(rights.decide).toHaveBeenCalledTimes(2);
  });
});
