import { NotFoundException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { UsersService } from './users.service';

jest.mock('argon2', () => ({ verify: jest.fn() }));

describe('UsersService account security', () => {
  const prisma = {
    user: {
      findUnique: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
  };
  const service = new UsersService(prisma as any);

  beforeEach(() => {
    jest.clearAllMocks();
    (argon2.verify as jest.Mock).mockResolvedValue(true);
  });

  it('requires a valid password before deleting the account', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-a',
      passwordHash: 'argon-hash',
    });
    prisma.user.delete.mockResolvedValue({ id: 'user-a' });

    await expect(service.delete('user-a', 'current-password')).resolves.toEqual({
      deleted: true,
    });
    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { id: 'user-a' },
      select: { id: true, passwordHash: true },
    });
    expect(argon2.verify).toHaveBeenCalledWith('argon-hash', 'current-password');
    expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: 'user-a' } });
  });

  it('does not delete an account when password reauthentication fails', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-a',
      passwordHash: 'argon-hash',
    });
    (argon2.verify as jest.Mock).mockResolvedValue(false);

    await expect(service.delete('user-a', 'wrong-password'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.delete).not.toHaveBeenCalled();
  });

  it('does not delete an account that no longer exists', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.delete('missing-user', 'password'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(argon2.verify).not.toHaveBeenCalled();
    expect(prisma.user.delete).not.toHaveBeenCalled();
  });
});
