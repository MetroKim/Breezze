import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../prisma.service';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly prisma: PrismaService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: process.env.JWT_SECRET ?? 'dev-only-secret-change-me',
    });
  }

  async validate(payload: { sub: string; sid?: string; mfaVerified?: boolean }) {
    if (!payload.sid) {
      throw new UnauthorizedException('SESSION_INVALID');
    }

    // An access JWT is valid only while its refresh-token family has an
    // unrevoked, unexpired member. Revoking one session therefore invalidates
    // its access JWTs on the next API request, not merely after 15 minutes.
    const user = await this.prisma.user.findFirst({
      where: {
        id: payload.sub,
        refreshTokens: {
          some: {
            familyId: payload.sid,
            revokedAt: null,
            expiresAt: { gt: new Date() },
          },
        },
      },
      select: { id: true, email: true, role: true, mfaEnabled: true },
    });
    if (!user) throw new UnauthorizedException('SESSION_INVALID');
    return { ...user, sessionId: payload.sid, mfaVerified: payload.mfaVerified === true };
  }
}
