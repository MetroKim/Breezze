import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma.service';
import { AuthService } from './auth.service';
import { encryptTotpSecret } from './totp';

describe('AuthService TOTP enrollment and verification', () => {
  let service: AuthService;
  let prisma: any;
  let jwt: Pick<JwtService, 'signAsync'>;
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date(59_000));
    process.env.MFA_ENCRYPTION_KEY = Buffer.alloc(32, 9).toString('base64');
    const tx = {
      user: {
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      refreshToken: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      adminAuditEvent: { create: jest.fn().mockResolvedValue({}) },
    };
    prisma = {
      user: {
        findUnique: jest.fn(),
        update: jest.fn().mockResolvedValue({}),
      },
      refreshToken: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)),
      tx,
    };
    jwt = { signAsync: jest.fn().mockResolvedValue('mfa-verified-access-token') };
    service = new AuthService(prisma as PrismaService, jwt as JwtService);
  });

  afterEach(() => jest.useRealTimers());

  it('creates an encrypted pending secret and authenticator provisioning URI', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      mfaEnabled: false,
    });
    const result = await service.beginMfaSetup('admin-1');

    expect(result.provisioningUri).toContain('otpauth://totp/Breezze%3Aadmin%40example.com');
    expect(result.secret).toMatch(/^[A-Z2-7]+$/);
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'admin-1' },
      data: { mfaPendingSecretCiphertext: expect.any(String) },
    });
    expect(prisma.user.update.mock.calls[0][0].data.mfaPendingSecretCiphertext)
      .not.toContain(result.secret);
  });

  it('enables MFA only after a valid TOTP and upgrades the current session', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: 'admin',
      mfaEnabled: false,
      mfaPendingSecretCiphertext: encryptTotpSecret(secret),
    });

    await expect(service.verifyMfaSetup('admin-1', 'family-1', '287082')).resolves.toEqual({
      verified: true,
      accessToken: 'mfa-verified-access-token',
    });
    expect(prisma.tx.user.updateMany).toHaveBeenCalledWith({
      where: { id: 'admin-1', OR: [{ mfaLastUsedStep: null }, { mfaLastUsedStep: { lt: BigInt(1) } }] },
      data: { mfaLastUsedStep: BigInt(1) },
    });
    expect(prisma.tx.user.update).toHaveBeenCalledWith({
      where: { id: 'admin-1' },
      data: {
        mfaEnabled: true,
        mfaSecretCiphertext: expect.any(String),
        mfaPendingSecretCiphertext: null,
      },
    });
    expect(prisma.tx.adminAuditEvent.create).toHaveBeenCalledWith({
      data: {
        actorId: 'admin-1',
        action: 'admin.mfa.enabled',
        targetType: 'user',
        targetId: 'admin-1',
        metadata: { method: 'totp' },
      },
    });
    expect(prisma.tx.refreshToken.updateMany).toHaveBeenCalledWith({
      where: {
        userId: 'admin-1',
        familyId: 'family-1',
        revokedAt: null,
        expiresAt: { gt: expect.any(Date) },
      },
      data: { mfaVerified: true },
    });
    expect(jwt.signAsync).toHaveBeenCalledWith(
      { sub: 'admin-1', email: 'admin@example.com', sid: 'family-1', mfaVerified: true },
      { expiresIn: '15m' },
    );
  });

  it('does not enable MFA with an invalid code', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: 'admin',
      mfaEnabled: false,
      mfaPendingSecretCiphertext: encryptTotpSecret(secret),
    });

    await expect(service.verifyMfaSetup('admin-1', 'family-1', '000000'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects reuse of a previously accepted TOTP time step', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: 'admin',
      mfaEnabled: false,
      mfaPendingSecretCiphertext: encryptTotpSecret(secret),
    });
    prisma.tx.user.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.verifyMfaSetup('admin-1', 'family-1', '287082'))
      .rejects.toThrow('MFA_CODE_REPLAYED');
    expect(prisma.tx.user.update).not.toHaveBeenCalled();
    expect(prisma.tx.refreshToken.updateMany).not.toHaveBeenCalled();
  });

  it('requires an enrolled secret to verify a login session', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      mfaEnabled: false,
      mfaSecretCiphertext: null,
    });
    await expect(service.verifyMfa('admin-1', 'family-1', '287082'))
      .rejects.toThrow('MFA_NOT_CONFIGURED');
    expect(prisma.refreshToken.updateMany).not.toHaveBeenCalled();
  });
});
