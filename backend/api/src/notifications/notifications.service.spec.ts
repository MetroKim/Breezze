import { ConflictException } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

describe('NotificationsService push-token ownership', () => {
  const prisma = {
    pushToken: {
      findUnique: jest.fn(),
      create: jest.fn(),
      updateMany: jest.fn(),
    },
    notification: { findMany: jest.fn(), create: jest.fn(), updateMany: jest.fn() },
  };
  const service = new NotificationsService(prisma as any);

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.pushToken.updateMany.mockResolvedValue({ count: 1 });
  });

  it('rejects registering a token already owned by another account', async () => {
    prisma.pushToken.findUnique.mockResolvedValue({ userId: 'owner-a' });
    await expect(service.registerToken('owner-b', 'device-token', 'ios'))
      .rejects.toThrow(ConflictException);
    expect(prisma.pushToken.create).not.toHaveBeenCalled();
    expect(prisma.pushToken.updateMany).not.toHaveBeenCalled();
  });

  it('lets the existing owner update platform using an owner-scoped write', async () => {
    prisma.pushToken.findUnique
      .mockResolvedValueOnce({ userId: 'owner-a' })
      .mockResolvedValueOnce({ userId: 'owner-a', token: 'device-token', platform: 'android' });

    await service.registerToken('owner-a', 'device-token', 'android');

    expect(prisma.pushToken.updateMany).toHaveBeenCalledWith({
      where: { token: 'device-token', userId: 'owner-a' },
      data: { platform: 'android' },
    });
    expect(prisma.pushToken.create).not.toHaveBeenCalled();
  });

  it('creates a token when it is not registered', async () => {
    const created = { userId: 'owner-a', token: 'device-token', platform: 'ios' };
    prisma.pushToken.findUnique.mockResolvedValue(null);
    prisma.pushToken.create.mockResolvedValue(created);

    await expect(service.registerToken('owner-a', 'device-token', 'ios')).resolves.toBe(created);
    expect(prisma.pushToken.create).toHaveBeenCalledWith({ data: created });
  });

  it('rejects a concurrent first-registration race won by another account', async () => {
    prisma.pushToken.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ userId: 'owner-b' });
    prisma.pushToken.create.mockRejectedValue({ code: 'P2002' });

    await expect(service.registerToken('owner-a', 'device-token', 'ios'))
      .rejects.toThrow(ConflictException);
    expect(prisma.pushToken.updateMany).not.toHaveBeenCalled();
  });

  it('recovers a concurrent first-registration race for the same account', async () => {
    const saved = { userId: 'owner-a', token: 'device-token', platform: 'android' };
    prisma.pushToken.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ userId: 'owner-a' })
      .mockResolvedValueOnce(saved);
    prisma.pushToken.create.mockRejectedValue({ code: 'P2002' });

    await expect(service.registerToken('owner-a', 'device-token', 'android')).resolves.toBe(saved);
    expect(prisma.pushToken.updateMany).toHaveBeenCalledWith({
      where: { token: 'device-token', userId: 'owner-a' },
      data: { platform: 'android' },
    });
  });
});
