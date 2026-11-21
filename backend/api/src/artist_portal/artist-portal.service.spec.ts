import { ArtistPortalService } from './artist-portal.service';

describe('ArtistPortalService tenant isolation', () => {
  const prisma = {
    artist: { findUnique: jest.fn() },
    artistClaim: { findFirst: jest.fn(), create: jest.fn(), findMany: jest.fn() },
    track: { findMany: jest.fn() },
    listeningEvent: { findMany: jest.fn() },
  };
  const service = new ArtistPortalService(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('creates an artist claim for the authenticated account only', async () => {
    prisma.artist.findUnique.mockResolvedValue({ id: 'artist-1' });
    prisma.artistClaim.findFirst.mockResolvedValue(null);
    prisma.artistClaim.create.mockResolvedValue({ userId: 'user-a', artistId: 'artist-1' });

    await service.claim('user-a', 'artist-1');
    expect(prisma.artistClaim.create).toHaveBeenCalledWith({
      data: { userId: 'user-a', artistId: 'artist-1', status: 'pending' },
    });
  });

  it('limits analytics to artist claims owned by the authenticated account', async () => {
    prisma.artistClaim.findMany.mockResolvedValue([]);
    await expect(service.analytics('user-a')).resolves.toEqual({
      artists: [],
      totals: { plays: 0 },
    });
    expect(prisma.artistClaim.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a', status: 'approved' },
      select: { artistId: true },
    });
    expect(prisma.track.findMany).not.toHaveBeenCalled();
    expect(prisma.listeningEvent.findMany).not.toHaveBeenCalled();
  });

  it('does not expose claims when another account already owns the artist claim', async () => {
    prisma.artist.findUnique.mockResolvedValue({ id: 'artist-1' });
    prisma.artistClaim.findFirst
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ userId: 'user-b', status: 'approved' });
    await expect(service.claim('user-a', 'artist-1')).rejects.toThrow('ARTIST_ALREADY_CLAIMED');
    expect(prisma.artistClaim.create).not.toHaveBeenCalled();
  });
  it('returns the existing claim when the same account retries', async () => {
    prisma.artist.findUnique.mockResolvedValue({ id: 'artist-1' });
    const existing = { id: 'claim-1', userId: 'user-a', artistId: 'artist-1', status: 'pending' };
    prisma.artistClaim.findFirst.mockResolvedValue(existing);

    await expect(service.claim('user-a', 'artist-1')).resolves.toBe(existing);
    expect(prisma.artistClaim.create).not.toHaveBeenCalled();
  });

  it('converts a concurrent duplicate insert into a conflict', async () => {
    prisma.artist.findUnique.mockResolvedValue({ id: 'artist-1' });
    prisma.artistClaim.findFirst.mockResolvedValue(null);
    prisma.artistClaim.create.mockRejectedValue({ code: 'P2002' });

    await expect(service.claim('user-a', 'artist-1'))
      .rejects.toThrow('ARTIST_CLAIM_ALREADY_EXISTS');
  });
});
