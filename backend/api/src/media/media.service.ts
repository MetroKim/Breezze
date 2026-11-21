import { Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { MediaSigner } from '../playback/media-signer.service';
import { mediaQueue, MediaJobData } from '../workers/media.queue';

@Injectable()
export class MediaService implements OnModuleInit {
  private queue: ReturnType<typeof mediaQueue> | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly signer: MediaSigner,
  ) {}

  async onModuleInit() {
    const redisUrl = process.env.REDIS_URL ?? 'redis://localhost:6379';
    this.queue = mediaQueue(redisUrl);
  }

  async registerUpload(
    userId: string,
    dto: { submissionId: string; originalFilename: string; bytes: number },
  ) {
    const job = await this.prisma.mediaJob.create({
      data: {
        userId,
        submissionId: dto.submissionId,
        originalFilename: dto.originalFilename,
        bytes: dto.bytes,
        status: 'quarantined',
      },
    });

    try {
      const upload = this.signer.createUploadUrl(
        userId,
        job.id,
        dto.originalFilename,
        dto.bytes,
      );
      return {
        job,
        uploadUrl: upload.url,
        uploadExpiresAt: upload.expiresAt,
        objectKey: upload.objectKey,
        requiredHeaders: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(dto.bytes) },
        completeEndpoint: `/api/v1/media/jobs/${job.id}/complete`,
      };
    } catch (error) {
      await this.prisma.mediaJob.updateMany({
        where: { id: job.id, userId },
        data: { status: 'rejected' },
      });
      throw error;
    }
  }

  async completeUpload(userId: string, jobId: string) {
    const result = await this.prisma.mediaJob.updateMany({
      where: { id: jobId, userId, status: 'quarantined' },
      data: { status: 'uploaded' },
    });
    if (result.count === 0) throw new NotFoundException('UPLOAD_JOB_NOT_FOUND');

    const job = await this.prisma.mediaJob.findFirst({
      where: { id: jobId, userId },
    });
    if (!job) throw new NotFoundException('UPLOAD_JOB_NOT_FOUND');

    if (!this.queue) throw new Error('MEDIA_QUEUE_UNAVAILABLE');
    await this.queue.add('pipeline', {
      jobId: job.id,
      submissionId: job.submissionId,
      inputPath: `quarantine/${userId}/${job.id}/${job.originalFilename.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120)}`,
    } satisfies MediaJobData);

    return { jobId, status: 'uploaded', queued: true };
  }

  async listJobs(userId: string) {
    return this.prisma.mediaJob.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }
}
