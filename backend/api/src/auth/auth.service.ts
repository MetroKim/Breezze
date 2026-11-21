import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { PrismaService } from '../prisma.service';
import {
  decryptTotpSecret,
  encryptTotpSecret,
  generateTotpSecret,
  totpProvisioningUri,
  getVerifiedTotpCounter,
} from './totp';

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  mfaRequired?: boolean;
  user: { id: string; email: string; displayName: string | null };
}

type AuthUser = {
  id: string;
  email: string;
  displayName: string | null;
  role?: string;
  mfaEnabled?: boolean;
};

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  private hashRefreshToken(token: string): string {
    return createHash('sha256').update(token, 'utf8').digest('hex');
  }

  private refreshExpiry(): Date {
    return new Date(Date.now() + 30 * 24 * 3600 * 1000);
  }

  private async issueTokens(
    user: AuthUser,
    refreshOverride?: string,
    existingFamilyId?: string,
    mfaVerified = false,
  ): Promise<AuthResult> {
    const familyId = existingFamilyId ?? randomUUID();
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, sid: familyId, mfaVerified },
      { expiresIn: '15m' },
    );
    const refreshToken = refreshOverride ?? randomBytes(32).toString('hex');
    if (!refreshOverride) {
      await this.prisma.refreshToken.create({
        data: {
          tokenHash: this.hashRefreshToken(refreshToken),
          familyId,
          userId: user.id,
          expiresAt: this.refreshExpiry(),
          mfaVerified,
        },
      });
    }
    const mfaRequired = (user.role === 'admin' || user.mfaEnabled === true) && !mfaVerified;
    return {
      accessToken,
      refreshToken,
      ...(mfaRequired ? { mfaRequired: true } : {}),
      user: { id: user.id, email: user.email, displayName: user.displayName },
    };
  }

  async register(
    email: string,
    password: string,
    displayName?: string,
  ): Promise<AuthResult> {
    const exists = await this.prisma.user.findUnique({ where: { email } });
    if (exists) throw new ConflictException('EMAIL_TAKEN');

    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    const user = await this.prisma.user.create({
      data: { email, passwordHash, displayName: displayName ?? null },
    });
    return this.issueTokens(user);
  }

  async login(email: string, password: string): Promise<AuthResult> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user) throw new UnauthorizedException('INVALID_CREDENTIALS');

    const valid = await argon2
      .verify(user.passwordHash, password)
      .catch(() => false);
    if (!valid) throw new UnauthorizedException('INVALID_CREDENTIALS');
    return this.issueTokens(user);
  }

  async refresh(refreshToken: string): Promise<AuthResult> {
    const token = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: this.hashRefreshToken(refreshToken) },
      include: { user: true },
    });

    if (!token || token.revokedAt !== null || token.expiresAt < new Date()) {
      if (token) {
        await this.prisma.refreshToken.updateMany({
          where: { familyId: token.familyId, revokedAt: null },
          data: { revokedAt: new Date() },
        });
      }
      throw new UnauthorizedException('REFRESH_REUSED_OR_INVALID');
    }

    const rotated = randomBytes(32).toString('hex');
    const consumed = await this.prisma.$transaction(async (tx) => {
      const result = await tx.refreshToken.updateMany({
        where: { id: token.id, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      if (result.count !== 1) {
        await tx.refreshToken.updateMany({
          where: { familyId: token.familyId, revokedAt: null },
          data: { revokedAt: new Date() },
        });
        return false;
      }
      await tx.refreshToken.create({
        data: {
          tokenHash: this.hashRefreshToken(rotated),
          familyId: token.familyId,
          userId: token.userId,
          expiresAt: this.refreshExpiry(),
          mfaVerified: token.mfaVerified,
        },
      });
      return true;
    });
    if (!consumed) throw new UnauthorizedException('REFRESH_REUSED_OR_INVALID');

    return this.issueTokens(token.user, rotated, token.familyId, token.mfaVerified);
  }

  async beginMfaSetup(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, mfaEnabled: true },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');
    if (user.mfaEnabled) throw new ConflictException('MFA_ALREADY_ENABLED');

    const secret = generateTotpSecret();
    await this.prisma.user.update({
      where: { id: userId },
      data: { mfaPendingSecretCiphertext: encryptTotpSecret(secret) },
    });
    return {
      secret,
      provisioningUri: totpProvisioningUri(secret, user.email),
      algorithm: 'SHA1',
      digits: 6,
      periodSeconds: 30,
    };
  }

  async verifyMfaSetup(userId: string, sessionId: string, code: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, displayName: true, role: true, mfaEnabled: true, mfaPendingSecretCiphertext: true },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');
    if (user.mfaEnabled || !user.mfaPendingSecretCiphertext) {
      throw new ConflictException('MFA_SETUP_NOT_PENDING');
    }

    const secret = decryptTotpSecret(user.mfaPendingSecretCiphertext);
    const counter = getVerifiedTotpCounter(secret, code);
    if (counter === null) throw new UnauthorizedException('MFA_CODE_INVALID');

    await this.prisma.$transaction(async (tx) => {
      const accepted = await tx.user.updateMany({
        where: { id: userId, OR: [{ mfaLastUsedStep: null }, { mfaLastUsedStep: { lt: BigInt(counter) } }] },
        data: { mfaLastUsedStep: BigInt(counter) },
      });
      if (accepted.count === 0) throw new UnauthorizedException('MFA_CODE_REPLAYED');
      await tx.user.update({
        where: { id: userId },
        data: {
          mfaEnabled: true,
          mfaSecretCiphertext: user.mfaPendingSecretCiphertext,
          mfaPendingSecretCiphertext: null,
        },
      });
      const verified = await tx.refreshToken.updateMany({
        where: { userId, familyId: sessionId, revokedAt: null, expiresAt: { gt: new Date() } },
        data: { mfaVerified: true },
      });
      if (verified.count === 0) throw new UnauthorizedException('SESSION_INVALID');
    });

    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, sid: sessionId, mfaVerified: true },
      { expiresIn: '15m' },
    );
    return { verified: true, accessToken };
  }

  async verifyMfa(userId: string, sessionId: string, code: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, mfaEnabled: true, mfaSecretCiphertext: true },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');
    if (!user.mfaEnabled || !user.mfaSecretCiphertext) {
      throw new UnauthorizedException('MFA_NOT_CONFIGURED');
    }
    const counter = getVerifiedTotpCounter(decryptTotpSecret(user.mfaSecretCiphertext), code);
    if (counter === null) throw new UnauthorizedException('MFA_CODE_INVALID');

    await this.prisma.$transaction(async (tx) => {
      const accepted = await tx.user.updateMany({
        where: { id: userId, OR: [{ mfaLastUsedStep: null }, { mfaLastUsedStep: { lt: BigInt(counter) } }] },
        data: { mfaLastUsedStep: BigInt(counter) },
      });
      if (accepted.count === 0) throw new UnauthorizedException('MFA_CODE_REPLAYED');
      const updated = await tx.refreshToken.updateMany({
        where: { userId, familyId: sessionId, revokedAt: null, expiresAt: { gt: new Date() } },
        data: { mfaVerified: true },
      });
      if (updated.count === 0) throw new UnauthorizedException('SESSION_INVALID');
    });

    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, sid: sessionId, mfaVerified: true },
      { expiresIn: '15m' },
    );
    return { verified: true, accessToken };
  }

  async logout(refreshToken: string): Promise<void> {
    const token = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: this.hashRefreshToken(refreshToken) },
      select: { familyId: true, userId: true },
    });
    if (!token) return;

    await this.prisma.refreshToken.updateMany({
      where: { familyId: token.familyId, userId: token.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async profile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        displayName: true,
        createdAt: true,
      },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');
    return user;
  }

  async listSessions(userId: string) {
    return this.prisma.refreshToken.findMany({
      where: { userId, revokedAt: null },
      select: { id: true, createdAt: true, expiresAt: true },
    });
  }

  async revokeSession(userId: string, tokenId: string): Promise<void> {
    const sessionToken = await this.prisma.refreshToken.findFirst({
      where: { id: tokenId, userId, revokedAt: null },
      select: { familyId: true },
    });
    if (!sessionToken) throw new NotFoundException('SESSION_NOT_FOUND');

    await this.prisma.refreshToken.updateMany({
      where: { familyId: sessionToken.familyId, userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
}
