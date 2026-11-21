import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy session and MFA claims', () => {
  const prisma = { user: { findFirst: jest.fn() } };
  const strategy = new JwtStrategy(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('requires an active, unexpired refresh-token family and carries MFA state from the signed JWT', async () => {
    const user = { id: 'user-1', email: 'listener@example.com', role: 'admin' };
    prisma.user.findFirst.mockResolvedValue(user);

    await expect(strategy.validate({
      sub: 'user-1',
      sid: 'family-1',
      mfaVerified: true,
    })).resolves.toEqual({
      ...user,
      sessionId: 'family-1',
      mfaVerified: true,
    });
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

  it('marks an otherwise valid session as not MFA verified when claim is absent', async () => {
    prisma.user.findFirst.mockResolvedValue({ id: 'user-1', role: 'admin' });
    await expect(strategy.validate({ sub: 'user-1', sid: 'family-1' }))
      .resolves.toMatchObject({ sessionId: 'family-1', mfaVerified: false });
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
