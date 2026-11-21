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
  const queue = { add: jest.fn(), getJob: jest.fn() };
  const service = new MediaService(prisma as any, signer as any);

  beforeEach(() => {
    jest.clearAllMocks();
    (service as any).queue = queue;
  });

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
    prisma.mediaJob.findFirst.mockResolvedValue(null);
    await expect(service.completeUpload('user-a', 'job-owned-by-user-b'))
      .rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.mediaJob.updateMany).toHaveBeenCalledWith({
      where: { id: 'job-owned-by-user-b', userId: 'user-a', status: 'quarantined' },
      data: { status: 'uploaded' },
    });
    expect(prisma.mediaJob.findFirst).toHaveBeenCalledWith({
      where: { id: 'job-owned-by-user-b', userId: 'user-a' },
    });
    expect(queue.add).not.toHaveBeenCalled();
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
  it('retries queue insertion safely after Redis fails following the DB state change', async () => {
    const job = {
      id: 'job-1',
      userId: 'user-a',
      submissionId: 'release-1',
      originalFilename: 'track.wav',
      status: 'uploaded',
    };
    prisma.mediaJob.updateMany
      .mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 });
    prisma.mediaJob.findFirst.mockResolvedValue(job);
    queue.add.mockRejectedValueOnce(new Error('REDIS_UNAVAILABLE'))
      .mockResolvedValueOnce({});

    await expect(service.completeUpload('user-a', 'job-1'))
      .rejects.toThrow('REDIS_UNAVAILABLE');
    await expect(service.completeUpload('user-a', 'job-1')).resolves.toEqual({
      jobId: 'job-1',
      status: 'uploaded',
      queued: true,
    });

    expect(queue.add).toHaveBeenCalledTimes(2);
    expect(queue.add).toHaveBeenLastCalledWith(
      'pipeline',
      {
        jobId: 'job-1',
        submissionId: 'release-1',
        inputPath: 'quarantine/user-a/job-1/track.wav',
      },
      expect.objectContaining({
        jobId: 'media_job-1',
        attempts: 5,
        backoff: { type: 'exponential', delay: 1_000 },
      }),
    );
  });

  it('does not enqueue a second pipeline while the worker is already processing', async () => {
    prisma.mediaJob.updateMany.mockResolvedValue({ count: 0 });
    prisma.mediaJob.findFirst.mockResolvedValue({
      id: 'job-2',
      userId: 'user-a',
      status: 'processing',
    });

    await expect(service.completeUpload('user-a', 'job-2')).resolves.toEqual({
      jobId: 'job-2',
      status: 'processing',
      queued: true,
    });
    expect(queue.add).not.toHaveBeenCalled();
  });

  it('retries a terminal failed upload by removing the retained failed BullMQ job', async () => {
    const remove = jest.fn().mockResolvedValue(undefined);
    const existing = { getState: jest.fn().mockResolvedValue('failed'), remove };
    prisma.mediaJob.updateMany.mockResolvedValue({ count: 1 });
    prisma.mediaJob.findFirst.mockResolvedValue({
      id: 'job-failed', userId: 'user-a', submissionId: 'release-1',
      originalFilename: 'track.wav', status: 'failed',
    });
    queue.getJob.mockResolvedValue(existing);
    queue.add.mockResolvedValue({});

    await expect(service.retryFailedUpload('user-a', 'job-failed')).resolves.toEqual({
      jobId: 'job-failed', status: 'uploaded', queued: true,
    });
    expect(queue.getJob).toHaveBeenCalledWith('media_job-failed');
    expect(remove).toHaveBeenCalledTimes(1);
    expect(queue.add).toHaveBeenCalledWith(
      'pipeline',
      expect.objectContaining({ jobId: 'job-failed', submissionId: 'release-1' }),
      expect.objectContaining({ jobId: 'media_job-failed', attempts: 5 }),
    );
  });

  it('does not retry another account failed upload', async () => {
    prisma.mediaJob.updateMany.mockResolvedValue({ count: 0 });
    prisma.mediaJob.findFirst.mockResolvedValue(null);
    await expect(service.retryFailedUpload('user-a', 'job-owned-by-user-b'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(queue.getJob).not.toHaveBeenCalled();
    expect(queue.add).not.toHaveBeenCalled();
  });

  it('restores failed state when retry enqueue fails so the owner can retry later', async () => {
    prisma.mediaJob.updateMany
      .mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 1 });
    prisma.mediaJob.findFirst.mockResolvedValue({
      id: 'job-failed', userId: 'user-a', submissionId: 'release-1',
      originalFilename: 'track.wav', status: 'failed',
    });
    queue.getJob.mockResolvedValue(null);
    queue.add.mockRejectedValue(new Error('REDIS_UNAVAILABLE'));

    await expect(service.retryFailedUpload('user-a', 'job-failed'))
      .rejects.toThrow('REDIS_UNAVAILABLE');
    expect(prisma.mediaJob.updateMany).toHaveBeenLastCalledWith({
      where: { id: 'job-failed', userId: 'user-a', status: 'uploaded' },
      data: { status: 'failed' },
    });
  });

});
