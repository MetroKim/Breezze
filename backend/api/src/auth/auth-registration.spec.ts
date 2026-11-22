import { ConflictException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma.service';
import { AuthService } from './auth.service';

describe('AuthService email normalization', () => {
  const prisma = {
    user: {
      findFirst: jest.fn(),
      create: jest.fn(),
    },
    refreshToken: {
      create: jest.fn(),
    },
  };
  const jwt = { signAsync: jest.fn().mockResolvedValue('access-token') };
  let service: AuthService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.user.findFirst.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({
      id: 'user-1',
      email: 'listener@example.com',
      displayName: 'Listener',
      role: 'user',
      mfaEnabled: false,
    });
    prisma.refreshToken.create.mockResolvedValue({ id: 'refresh-1' });
    jest.spyOn(argon2, 'hash').mockResolvedValue('argon2id-hash');
    service = new AuthService(
      prisma as unknown as PrismaService,
      jwt as unknown as JwtService,
    );
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('stores trimmed lowercase email addresses', async () => {
    await service.register('  Listener@Example.COM  ', 'correct horse battery', 'Listener');

    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: { email: { equals: 'listener@example.com', mode: 'insensitive' } },
      select: { id: true },
    });
    expect(prisma.user.create).toHaveBeenCalledWith({
      data: {
        email: 'listener@example.com',
        passwordHash: 'argon2id-hash',
        displayName: 'Listener',
      },
    });
  });

  it('rejects case-insensitive duplicate email addresses', async () => {
    prisma.user.findFirst.mockResolvedValue({ id: 'existing-user' });

    await expect(
      service.register('LISTENER@example.com', 'correct horse battery'),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('maps a concurrent unique-index conflict to EMAIL_TAKEN', async () => {
    prisma.user.create.mockRejectedValue({ code: 'P2002' });

    await expect(
      service.register('listener@example.com', 'correct horse battery'),
    ).rejects.toThrow('EMAIL_TAKEN');
  });
});
