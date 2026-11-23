import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

// Plan §13.2 — content reports, copyright complaints, UGC review.
@Injectable()
export class ModerationService {
  constructor(private readonly prisma: PrismaService) {}

  async fileReport(
    reporterId: string,
    dto: { targetType: string; targetId: string; reason: string },
  ) {
    return this.prisma.contentReport.create({
      data: {
        reporterId,
        targetType: dto.targetType,
        targetId: dto.targetId,
        reason: dto.reason,
      },
    });
  }

  async listOpen() {
    return this.prisma.contentReport.findMany({
      where: { status: 'open' },
      orderBy: { createdAt: 'asc' },
      take: 50,
    });
  }

  async resolve(
    actorId: string,
    reportId: string,
    resolution: 'dismissed' | 'actioned',
  ) {
    return this.prisma.$transaction(async (tx) => {
      const result = await tx.contentReport.updateMany({
        where: { id: reportId, status: 'open' },
        data: { status: resolution },
      });
      if (result.count === 0) {
        throw new NotFoundException('REPORT_NOT_FOUND_OR_RESOLVED');
      }

      await tx.adminAuditEvent.create({
        data: {
          actorId,
          action: 'moderation.report.resolved',
          targetType: 'content_report',
          targetId: reportId,
          metadata: { resolution },
        },
      });
      return { resolved: true, resolution };
    });
  }
}
