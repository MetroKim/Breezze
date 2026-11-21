import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

// Plan §15.17 — distributor release submissions, validation, delivery
// status. Ingestion workers (Plan §10) consume validated submissions.
@Injectable()
export class DistributorService {
  constructor(private readonly prisma: PrismaService) {}

  async submitRelease(
    userId: string,
    dto: {
      title: string;
      artistName: string;
      trackTitles: string[];
    },
  ) {
    const artist = await this.prisma.artist.upsert({
      where: { name: dto.artistName },
      create: { name: dto.artistName },
      update: {},
    });

    return this.prisma.releaseSubmission.create({
      data: {
        userId,
        title: dto.title,
        artistId: artist.id,
        trackCount: dto.trackTitles.length,
        status: 'submitted',
      },
    });
  }

  async mySubmissions(userId: string) {
    return this.prisma.releaseSubmission.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async validate(actorId: string, submissionId: string) {
    return this.prisma.$transaction(async (tx) => {
      const submission = await tx.releaseSubmission.findUnique({
        where: { id: submissionId },
      });
      if (!submission) throw new NotFoundException('SUBMISSION_NOT_FOUND');

      const errors: string[] = [];
      if (submission.title.trim().length === 0) errors.push('TITLE_EMPTY');
      if (submission.trackCount < 1) errors.push('NO_TRACKS');

      const status = errors.length > 0 ? 'invalid' : 'validated';
      const updated = await tx.releaseSubmission.updateMany({
        where: { id: submissionId, status: submission.status },
        data: { status },
      });
      if (updated.count === 0) {
        throw new NotFoundException('SUBMISSION_NOT_FOUND_OR_CHANGED');
      }

      await tx.adminAuditEvent.create({
        data: {
          actorId,
          action: 'distributor.release.validated',
          targetType: 'release_submission',
          targetId: submissionId,
          metadata: { previousStatus: submission.status, newStatus: status, errors },
        },
      });
      return { status, errors };
    });
  }}
