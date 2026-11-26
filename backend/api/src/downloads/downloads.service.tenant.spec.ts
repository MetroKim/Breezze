import { DownloadsService } from './downloads.service';

describe('DownloadsService tenant isolation', () => {
  const prisma = {
    track: { findUnique: jest.fn() },
    audioAssetVariant: { findUnique: jest.fn() },
    downloadRecord: {
      findMany: jest.fn(),
      deleteMany: jest.fn(),
      upsert: jest.fn(),
    },
  };
  const rights = { decide: jest.fn() };
  const signer = { createPlaybackUrl: jest.fn() };
  const providers = { get: jest.fn() };
  let service: DownloadsService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({ id: 'track-1', source: null, externalId: null });
    prisma.audioAssetVariant.findUnique.mockResolvedValue({
      status: 'ready', verifiedAt: new Date(), sizeBytes: 1024n, mimeType: 'audio/mp4',
    });
    service = new DownloadsService(prisma as any, rights as any, signer as any, providers as any);
  });

  it('lists only the current user download records', async () => {
    prisma.downloadRecord.findMany.mockResolvedValue([]);
    await service.list('user-a');
    expect(prisma.downloadRecord.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a', status: 'active' },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        trackId: true,
        status: true,
        createdAt: true,
        expiresAt: true,
      },
    });
  });

  it('cannot delete another user download record', async () => {
    prisma.downloadRecord.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.remove('user-a', 'track-owned-by-b'))
      .rejects.toThrow('DOWNLOAD_NOT_FOUND');
    expect(prisma.downloadRecord.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-a', trackId: 'track-owned-by-b' },
    });
  });

  it('records download authorization for the current user and track', async () => {
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
      expiresAt: new Date('2027-01-01T00:00:00.000Z'),
      attribution: null,
    });
    signer.createPlaybackUrl.mockReturnValue({
      url: 'https://cdn.example/audio/track-1/download?sig=test',
      expiresAt: new Date(Date.now() + 60_000),
    });
    prisma.downloadRecord.upsert.mockResolvedValue({ id: 'download-1' });

    const result = await service.authorizeAndRecord('user-a', {
      trackId: 'track-1',
      territory: 'TZ',
    });

    expect(rights.decide).toHaveBeenCalledWith({
      userId: 'user-a',
      trackId: 'track-1',
      action: 'download',
      territory: 'TZ',
    });
    expect(prisma.downloadRecord.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId_trackId: { userId: 'user-a', trackId: 'track-1' } },
      create: expect.objectContaining({ userId: 'user-a', trackId: 'track-1' }),
    }));
    expect(result.allowed).toBe(true);
  });
});
