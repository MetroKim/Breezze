import { NotFoundException } from '@nestjs/common';
import { UsersService } from './users.service';

const png = (
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC' +
  'AAAAC0lEQVR42mP8/x8AAwMCAO+/+5AAAAAASUVORK5CYII='
);

describe('authenticated avatar persistence', () => {
  const prisma = {
    user: {
      updateMany: jest.fn(),
      findUnique: jest.fn(),
    },
  };
  const service = new UsersService(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('stores the selected thumbnail only under the authenticated account', async () => {
    prisma.user.updateMany.mockResolvedValue({ count: 1 });
    await expect(service.setAvatar('owner-a', png))
      .resolves.toEqual({ avatarPngBase64: png });
    expect(prisma.user.updateMany).toHaveBeenCalledWith({
      where: { id: 'owner-a' },
      data: { avatarPngBase64: png },
    });
  });

  it('does not let a session create/update another user', async () => {
    prisma.user.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.setAvatar('missing-user', png))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it('validates image content before the database and supports photo removal', async () => {
    await expect(service.setAvatar('owner-a', 'YWJj'))
      .rejects.toThrow('IMAGE_INVALID_PNG');
    expect(prisma.user.updateMany).not.toHaveBeenCalled();
    prisma.user.updateMany.mockResolvedValue({ count: 1 });
    await expect(service.setAvatar('owner-a', null))
      .resolves.toEqual({ avatarPngBase64: null });
  });
});
