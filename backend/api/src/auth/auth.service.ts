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

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  user: { id: string; email: string; displayName: string | null };
}

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
    user: { id: string; email: string; displayName: string | null },
    refreshOverride?: string,
    existingFamilyId?: string,
  ): Promise<AuthResult> {
    const familyId = existingFamilyId ?? randomUUID();
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, sid: familyId },
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
        },
      });
    }
    return {
      accessToken,
      refreshToken,
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
        },
      });
      return true;
    });
    if (!consumed) throw new UnauthorizedException('REFRESH_REUSED_OR_INVALID');

    return this.issueTokens(token.user, rotated, token.familyId);
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
