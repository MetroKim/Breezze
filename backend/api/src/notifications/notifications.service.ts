import { ConflictException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

// Plan §13.2 — templates, delivery (stub now, real push later),
// device tokens, history.
@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService) {}

  async registerToken(userId: string, token: string, platform: string) {
    const updateOwnedToken = async () => {
      const updated = await this.prisma.pushToken.updateMany({
        where: { token, userId },
        data: { platform },
      });
      if (updated.count !== 1) {
        throw new ConflictException('PUSH_TOKEN_ALREADY_REGISTERED');
      }
      const saved = await this.prisma.pushToken.findUnique({ where: { token } });
      if (!saved || saved.userId !== userId) {
        throw new ConflictException('PUSH_TOKEN_ALREADY_REGISTERED');
      }
      return saved;
    };

    const existing = await this.prisma.pushToken.findUnique({
      where: { token },
      select: { userId: true },
    });
    if (existing) {
      if (existing.userId !== userId) {
        throw new ConflictException('PUSH_TOKEN_ALREADY_REGISTERED');
      }
      return updateOwnedToken();
    }

    try {
      return await this.prisma.pushToken.create({
        data: { userId, token, platform },
      });
    } catch (error) {
      // A concurrent first registration may win the unique-token insert.
      // Re-read the winner and update only if it belongs to this same user.
      if (!error || typeof error !== 'object' || (error as { code?: string }).code !== 'P2002') {
        throw error;
      }
      const raced = await this.prisma.pushToken.findUnique({
        where: { token },
        select: { userId: true },
      });
      if (!raced || raced.userId !== userId) {
        throw new ConflictException('PUSH_TOKEN_ALREADY_REGISTERED');
      }
      return updateOwnedToken();
    }
  }

  async listForUser(userId: string) {
    return this.prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }

  async create(
    userId: string,
    dto: { title: string; body: string; kind?: string },
  ) {
    const notification = await this.prisma.notification.create({
      data: {
        userId,
        title: dto.title,
        body: dto.body,
        kind: dto.kind ?? 'general',
      },
    });
    // Delivery to FCM/APNs lands with the workers phase; the record
    // exists now so the history UI can be built against real data.
    return notification;
  }

  async markRead(userId: string, notificationId: string) {
    await this.prisma.notification.updateMany({
      where: { id: notificationId, userId },
      data: { readAt: new Date() },
    });
    return { read: true };
  }
}
