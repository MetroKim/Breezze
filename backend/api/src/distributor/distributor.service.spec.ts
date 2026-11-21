import { DistributorService } from './distributor.service';

describe('DistributorService tenant isolation', () => {
  const prisma = {
    artist: { upsert: jest.fn() },
    releaseSubmission: { create: jest.fn(), findMany: jest.fn(), findUnique: jest.fn(), update: jest.fn() },
  };
  const service = new DistributorService(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('binds a new release submission to the authenticated account', async () => {
    prisma.artist.upsert.mockResolvedValue({ id: 'artist-1' });
    prisma.releaseSubmission.create.mockResolvedValue({ id: 'release-1', userId: 'user-a' });

    await service.submitRelease('user-a', {
      title: 'Release',
      artistName: 'Artist',
      trackTitles: ['Track 1'],
    });

    expect(prisma.releaseSubmission.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-a',
        title: 'Release',
        artistId: 'artist-1',
        trackCount: 1,
        status: 'submitted',
      },
    });
  });

  it('lists only submissions owned by the authenticated account', async () => {
    prisma.releaseSubmission.findMany.mockResolvedValue([]);
    await service.mySubmissions('user-a');
    expect(prisma.releaseSubmission.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      orderBy: { createdAt: 'desc' },
    });
  });
});
