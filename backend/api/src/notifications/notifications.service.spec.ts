import { ConflictException } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

describe('NotificationsService push-token ownership', () => {
  const prisma = {
    pushToken: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
    },
    notification: { findMany: jest.fn(), create: jest.fn(), updateMany: jest.fn() },
  };
  const service = new NotificationsService(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('rejects registering a token already owned by another account', async () => {
    prisma.pushToken.findUnique.mockResolvedValue({ userId: 'owner-a' });
    await expect(service.registerToken('owner-b', 'device-token', 'ios'))
      .rejects.toThrow(ConflictException);
    expect(prisma.pushToken.upsert).not.toHaveBeenCalled();
  });

  it('allows the owner to refresh the platform metadata without changing ownership', async () => {
    prisma.pushToken.findUnique.mockResolvedValue({ userId: 'owner-a' });
    prisma.pushToken.upsert.mockResolvedValue({ userId: 'owner-a', token: 'device-token', platform: 'android' });
    await service.registerToken('owner-a', 'device-token', 'android');
    expect(prisma.pushToken.upsert).toHaveBeenCalledWith({
      where: { token: 'device-token' },
      create: { userId: 'owner-a', token: 'device-token', platform: 'android' },
      update: { platform: 'android' },
    });
  });
});
