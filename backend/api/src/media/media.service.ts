import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

// Plan §10.1 — media ingestion job records. The upload lands in
// quarantine storage (handled by the storage adapter), the job record
// drives the processing pipeline; the FFmpeg transcoding worker lands
// with the workers phase and consumes these records.
@Injectable()
export class MediaService {
  constructor(private readonly prisma: PrismaService) {}

  async registerUpload(
    userId: string,
    dto: { submissionId: string; originalFilename: string; bytes: number },
  ) {
    return this.prisma.mediaJob.create({
      data: {
        userId,
        submissionId: dto.submissionId,
        originalFilename: dto.originalFilename,
        bytes: dto.bytes,
        status: 'quarantined',
      },
    });
  }

  async markStatus(jobId: string, status: string) {
    const result = await this.prisma.mediaJob.updateMany({
      where: { id: jobId },
      data: { status },
    });
    if (result.count === 0) throw new NotFoundException('JOB_NOT_FOUND');
    return { jobId, status };
  }

  async listJobs(userId: string) {
    return this.prisma.mediaJob.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }
}
