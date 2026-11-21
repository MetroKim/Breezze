import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy session revocation', () => {
  const prisma = { user: { findFirst: jest.fn() } };
  const strategy = new JwtStrategy(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('requires an active, unexpired refresh-token family for access JWTs', async () => {
    const user = { id: 'user-1', email: 'listener@example.com' };
    prisma.user.findFirst.mockResolvedValue(user);

    await expect(strategy.validate({ sub: 'user-1', sid: 'family-1' })).resolves.toBe(user);
    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        id: 'user-1',
        refreshTokens: {
          some: {
            familyId: 'family-1',
            revokedAt: null,
            expiresAt: { gt: expect.any(Date) },
          },
        },
      },
    });
  });

  it('rejects access JWTs without a session identifier', async () => {
    await expect(strategy.validate({ sub: 'user-1' }))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
  });

  it('rejects access JWTs after their session family is revoked or expired', async () => {
    prisma.user.findFirst.mockResolvedValue(null);
    await expect(strategy.validate({ sub: 'user-1', sid: 'revoked-family' }))
      .rejects.toThrow('SESSION_INVALID');
  });
});
