import { UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma.service';
import { AuthService } from './auth.service';
import { encryptTotpSecret } from './totp';

jest.mock('argon2', () => ({ hash: jest.fn(), verify: jest.fn() }));

describe('AuthService TOTP enrollment and verification', () => {
  let service: AuthService;
  let prisma: any;
  let jwt: Pick<JwtService, 'signAsync'>;
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date(59_000));
    (argon2.verify as jest.Mock).mockResolvedValue(true);
    process.env.MFA_ENCRYPTION_KEY = Buffer.alloc(32, 9).toString('base64');
    const tx = {
      user: {
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      refreshToken: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      adminAuditEvent: { create: jest.fn().mockResolvedValue({}) },
      mfaRecoveryCode: {
        createMany: jest.fn().mockResolvedValue({ count: 10 }),
        findFirst: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
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

  afterEach(() => {
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('creates an encrypted pending secret and authenticator provisioning URI', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      passwordHash: 'argon-hash',
      role: 'admin',
      mfaEnabled: false,
    });
    const result = await service.beginMfaSetup('admin-1', 'fresh-password');
    expect(argon2.verify).toHaveBeenCalledWith('argon-hash', 'fresh-password');

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

    await expect(service.verifyMfaSetup('admin-1', 'family-1', '287082')).resolves.toMatchObject({
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
    expect(prisma.tx.mfaRecoveryCode.createMany).toHaveBeenCalledWith({
      data: expect.arrayContaining([
        expect.objectContaining({ userId: 'admin-1', codeHash: expect.stringMatching(/^[a-f0-9]{64}$/) }),
      ]),
    });
    expect(prisma.tx.mfaRecoveryCode.createMany.mock.calls[0][0].data).toHaveLength(10);
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

  it('consumes a recovery code once and verifies only the current session', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      role: 'admin',
      mfaEnabled: true,
      mfaSecretCiphertext: encryptTotpSecret(secret),
    });
    prisma.tx.mfaRecoveryCode.findFirst.mockResolvedValue({ id: 'recovery-1' });

    await expect(service.verifyMfa('admin-1', 'family-1', 'ABCD-EF01-2345-6789'))
      .resolves.toEqual({ verified: true, accessToken: 'mfa-verified-access-token' });

    expect(prisma.tx.mfaRecoveryCode.findFirst).toHaveBeenCalledWith({
      where: {
        userId: 'admin-1',
        codeHash: expect.stringMatching(/^[a-f0-9]{64}$/),
        consumedAt: null,
      },
      select: { id: true },
    });
    expect(prisma.tx.mfaRecoveryCode.updateMany).toHaveBeenCalledWith({
      where: { id: 'recovery-1', userId: 'admin-1', consumedAt: null },
      data: { consumedAt: expect.any(Date) },
    });
    expect(prisma.tx.adminAuditEvent.create).toHaveBeenCalledWith({
      data: {
        actorId: 'admin-1',
        action: 'admin.mfa.verified',
        targetType: 'user',
        targetId: 'admin-1',
        metadata: { method: 'recovery_code' },
      },
    });
  });

  it('requires an enrolled secret to verify a login session', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@example.com',
      role: 'admin',
      mfaEnabled: false,
      mfaSecretCiphertext: null,
    });
    await expect(service.verifyMfa('admin-1', 'family-1', '287082'))
      .rejects.toThrow('MFA_NOT_CONFIGURED');
    expect(prisma.refreshToken.updateMany).not.toHaveBeenCalled();
  });
});
