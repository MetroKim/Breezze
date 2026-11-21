import { DistributorService } from './distributor.service';

describe('DistributorService tenant isolation', () => {
  const prisma = {
    artist: { upsert: jest.fn() },
    releaseSubmission: { create: jest.fn(), findMany: jest.fn(), findUnique: jest.fn(), update: jest.fn() },
    $transaction: jest.fn(),
  };
  const tx = {
    releaseSubmission: { findUnique: jest.fn(), updateMany: jest.fn() },
    adminAuditEvent: { create: jest.fn() },
  };
  const service = new DistributorService(prisma as any);

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation((callback: (client: typeof tx) => unknown) => callback(tx));
  });

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
  it('audits administrator release validation in the same transaction', async () => {
    tx.releaseSubmission.findUnique.mockResolvedValue({
      id: 'release-1',
      title: 'Single',
      trackCount: 1,
      status: 'submitted',
    });
    tx.releaseSubmission.updateMany.mockResolvedValue({ count: 1 });
    tx.adminAuditEvent.create.mockResolvedValue({});

    await expect(service.validate('admin-1', 'release-1')).resolves.toEqual({
      status: 'validated',
      errors: [],
    });

    expect(tx.releaseSubmission.updateMany).toHaveBeenCalledWith({
      where: { id: 'release-1', status: 'submitted' },
      data: { status: 'validated' },
    });
    expect(tx.adminAuditEvent.create).toHaveBeenCalledWith({
      data: {
        actorId: 'admin-1',
        action: 'distributor.release.validated',
        targetType: 'release_submission',
        targetId: 'release-1',
        metadata: {
          previousStatus: 'submitted',
          newStatus: 'validated',
          errors: [],
        },
      },
    });
  });

  it('does not write an audit event if the release changes concurrently', async () => {
    tx.releaseSubmission.findUnique.mockResolvedValue({
      id: 'release-1',
      title: 'Single',
      trackCount: 1,
      status: 'submitted',
    });
    tx.releaseSubmission.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.validate('admin-1', 'release-1'))
      .rejects.toThrow('SUBMISSION_NOT_FOUND_OR_CHANGED');
    expect(tx.adminAuditEvent.create).not.toHaveBeenCalled();
  });

  it('does not write an audit event for a missing release', async () => {
    tx.releaseSubmission.findUnique.mockResolvedValue(null);

    await expect(service.validate('admin-1', 'missing'))
      .rejects.toThrow('SUBMISSION_NOT_FOUND');
    expect(tx.adminAuditEvent.create).not.toHaveBeenCalled();
  });
});
