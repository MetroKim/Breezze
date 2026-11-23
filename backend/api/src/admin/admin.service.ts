import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async dashboard() {
    const [users, tracks, albums, artists, playlists, takedowns] =
      await Promise.all([
        this.prisma.user.count(),
        this.prisma.track.count(),
        this.prisma.album.count(),
        this.prisma.artist.count(),
        this.prisma.playlist.count(),
        this.prisma.contentTakedownCase.count({ where: { status: 'active' } }),
      ]);
    return { users, tracks, albums, artists, playlists, activeTakedowns: takedowns };
  }

  async createUserRole(actorId: string, userId: string, role: string) {
    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.findUnique({ where: { id: userId }, select: { id: true, role: true } });
      if (!user) throw new NotFoundException('USER_NOT_FOUND');

      const updated = await tx.user.update({
        where: { id: userId },
        data: { role },
        select: { id: true, role: true },
      });

      await tx.adminAuditEvent.create({
        data: {
          actorId,
          action: 'user.role.updated',
          targetType: 'user',
          targetId: userId,
          metadata: { previousRole: user.role, newRole: role },
        },
      });
      return updated;
    });
  }

  async listTakedowns() {
    return this.prisma.contentTakedownCase.findMany({
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }

  async resolveTakedown(actorId: string, caseId: string) {
    return this.prisma.$transaction(async (tx) => {
      const resolved = await tx.contentTakedownCase.updateMany({
        where: { id: caseId, status: 'active' },
        data: { status: 'resolved' },
      });
      if (resolved.count === 0) {
        throw new NotFoundException('CASE_NOT_FOUND_OR_RESOLVED');
      }

      await tx.adminAuditEvent.create({
        data: {
          actorId,
          action: 'takedown.resolved',
          targetType: 'content_takedown_case',
          targetId: caseId,
          metadata: { newStatus: 'resolved' },
        },
      });
      return { resolved: true };
    });
  }

  async listAuditEvents() {
    return this.prisma.adminAuditEvent.findMany({
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }
}
