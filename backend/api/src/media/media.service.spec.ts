import { NotFoundException } from '@nestjs/common';
import { MediaService } from './media.service';

describe('MediaService tenant isolation', () => {
  const prisma = {
    releaseSubmission: { findFirst: jest.fn() },
    mediaJob: {
      create: jest.fn(),
      updateMany: jest.fn(),
      findFirst: jest.fn(),
      findMany: jest.fn(),
    },
  };
  const signer = { createUploadUrl: jest.fn() };
  const service = new MediaService(prisma as any, signer as any);

  beforeEach(() => jest.clearAllMocks());

  it('does not register an upload against another account release', async () => {
    prisma.releaseSubmission.findFirst.mockResolvedValue(null);
    await expect(service.registerUpload('user-a', {
      submissionId: 'release-owned-by-user-b',
      originalFilename: 'track.wav',
      bytes: 1024,
    })).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.releaseSubmission.findFirst).toHaveBeenCalledWith({
      where: { id: 'release-owned-by-user-b', userId: 'user-a' },
      select: { id: true },
    });
    expect(prisma.mediaJob.create).not.toHaveBeenCalled();
    expect(signer.createUploadUrl).not.toHaveBeenCalled();
  });

  it('does not complete another account upload job', async () => {
    prisma.mediaJob.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.completeUpload('user-a', 'job-owned-by-user-b'))
      .rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.mediaJob.updateMany).toHaveBeenCalledWith({
      where: { id: 'job-owned-by-user-b', userId: 'user-a', status: 'quarantined' },
      data: { status: 'uploaded' },
    });
    expect(prisma.mediaJob.findFirst).not.toHaveBeenCalled();
  });

  it('lists only jobs owned by the authenticated account', async () => {
    prisma.mediaJob.findMany.mockResolvedValue([]);
    await service.listJobs('user-a');
    expect(prisma.mediaJob.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  });
});
