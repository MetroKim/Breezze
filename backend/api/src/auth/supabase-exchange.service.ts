import {
  ConflictException,
  ForbiddenException,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { Prisma } from '@prisma/client';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { AuthService, AuthResult } from './auth.service';

interface VerifiedSupabaseUser {
  id: string;
  email: string;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Transitional login bridge. Supabase is the identity authority; the existing
 * Breezze session remains in use until the library/playlist foreign keys and
 * authenticated API endpoints have been migrated. Never trust identity or
 * email fields sent by the client or decoded without verification.
 *
 * This endpoint does not import/link existing email-password users. Explicit
 * proof of ownership is required before any legacy account can be linked.
 */
@Injectable()
export class SupabaseExchangeService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
  ) {}

  async exchange(accessToken: string): Promise<AuthResult> {
    const { subject, email } = await this.verifiedIdentity(accessToken);
    const userId = await this.findOrCreateBreezzeIdentity(subject, email);
    return this.auth.issueVerifiedSocialSession(
      userId, { supabaseVerified: true },
    );
  }

  /**
   * One-time, two-authority account linking. Supabase proves control of the
   * new identity; the Argon2 legacy password proves ownership of the *old*
   * Breezze user. Linking keeps the existing user ID and all owned data.
   *
   * Email matches alone, unverified Supabase JWTs, arbitrary client user IDs
   * and password-only links for privileged/MFA accounts are forbidden.
   */
  async linkLegacy(
    accessToken: string,
    legacyEmail: string,
    legacyPassword: string,
  ): Promise<AuthResult> {
    const { subject } = await this.verifiedIdentity(accessToken);
    const legacy = await this.prisma.user.findFirst({
      where: { email: { equals: legacyEmail.trim().toLowerCase(), mode: 'insensitive' } },
      select: { id: true, passwordHash: true, role: true, mfaEnabled: true },
    });
    const passwordValid = legacy
      ? await argon2.verify(legacy.passwordHash, legacyPassword).catch(() => false)
      : false;
    if (!legacy || !passwordValid) {
      throw new UnauthorizedException('LEGACY_CREDENTIALS_INVALID');
    }
    if (legacy.role !== 'user' || legacy.mfaEnabled) {
      throw new ForbiddenException('LEGACY_PRIVILEGED_LINK_BLOCKED');
    }

    const provider = 'supabase';
    let userId: string;
    try {
      userId = await this.prisma.$transaction(async (tx) => {
        const mapped = await tx.socialAuthIdentity.findUnique({
          where: { provider_subject: { provider, subject } },
          select: { userId: true },
        });
        if (mapped && mapped.userId !== legacy.id) {
          throw new ConflictException('SUPABASE_IDENTITY_ALREADY_LINKED');
        }

        // One Supabase subject per legacy account; serializable isolation
        // prevents concurrent distinct subjects from claiming the same user.
        const previouslyLinked = await tx.socialAuthIdentity.findFirst({
          where: { userId: legacy.id, provider },
          select: { subject: true },
        });
        if (previouslyLinked && previouslyLinked.subject !== subject) {
          throw new ConflictException('LEGACY_ALREADY_LINKED');
        }

        if (!mapped) {
          await tx.socialAuthIdentity.create({
            data: { userId: legacy.id, provider, subject },
          });
        }
        return legacy.id;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    } catch (error) {
      if ((error as { code?: string } | null)?.code === 'P2002' ||
          (error as { code?: string } | null)?.code === 'P2034') {
        // Unique-subject and concurrent-transaction collisions must never
        // silently reassign an existing identity to another account.
        throw new ConflictException('LEGACY_LINK_CONFLICT');
      }
      throw error;
    }

    return this.auth.issueVerifiedSocialSession(
      userId, { supabaseVerified: true },
    );
  }

  private async verifiedIdentity(
    accessToken: string,
  ): Promise<{ subject: string; email: string }> {
    const { url, key } = this.config();
    if (typeof accessToken !== 'string' ||
        accessToken.length < 20 ||
        accessToken.length > 8192 ||
        !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(accessToken)) {
      throw new UnauthorizedException('SUPABASE_TOKEN_INVALID');
    }
    const verified = await this.verifyAtSupabase(url, key, accessToken);
    // Bind identity to the verified provider project, not a client claim.
    return { subject: `${url.hostname}:${verified.id}`, email: verified.email };
  }

  private config(): { url: URL; key: string } {
    const rawUrl = process.env.SUPABASE_URL?.trim();
    const key = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
    if (!rawUrl || !key) {
      throw new ServiceUnavailableException('SUPABASE_AUTH_NOT_CONFIGURED');
    }
    try {
      const url = new URL(rawUrl);
      if (url.protocol !== 'https:' ||
          !url.hostname.endsWith('.supabase.co') ||
          url.username || url.password || url.search || url.hash ||
          (url.pathname !== '/' && url.pathname !== '')) {
        throw new Error('invalid origin');
      }
      return { url, key };
    } catch {
      throw new ServiceUnavailableException('SUPABASE_AUTH_CONFIGURATION_INVALID');
    }
  }

  private async verifyAtSupabase(
    url: URL,
    key: string,
    token: string,
  ): Promise<VerifiedSupabaseUser> {
    let response: Response;
    try {
      response = await fetch(new URL('/auth/v1/user', url), {
        method: 'GET',
        headers: {
          apikey: key,
          Authorization: `Bearer ${token}`,
          Accept: 'application/json',
        },
        redirect: 'error',
        signal: AbortSignal.timeout(5000),
      });
    } catch {
      // Never silently accept a token when Supabase cannot be reached.
      throw new ServiceUnavailableException('SUPABASE_AUTH_UNAVAILABLE');
    }

    if (response.status === 401 || response.status === 403) {
      throw new UnauthorizedException('SUPABASE_TOKEN_REJECTED');
    }
    if (!response.ok) {
      throw new ServiceUnavailableException('SUPABASE_AUTH_UNAVAILABLE');
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new UnauthorizedException('SUPABASE_USER_INVALID');
    }
    if (!body || typeof body !== 'object') {
      throw new UnauthorizedException('SUPABASE_USER_INVALID');
    }
    const user = body as Record<string, unknown>;
    const id = user.id;
    const email = user.email;
    if (typeof id !== 'string' || !UUID_PATTERN.test(id) ||
        typeof email !== 'string' || email.length > 320 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        typeof user.email_confirmed_at !== 'string' ||
        user.email_confirmed_at.length === 0 ||
        user.is_anonymous === true) {
      throw new UnauthorizedException('SUPABASE_EMAIL_NOT_VERIFIED');
    }
    return { id, email: email.trim().toLowerCase() };
  }

  private async findOrCreateBreezzeIdentity(
    subject: string,
    email: string,
  ): Promise<string> {
    const identityKey = { provider: 'supabase', subject };
    const mapped = await this.prisma.socialAuthIdentity.findUnique({
      where: { provider_subject: identityKey },
      select: { userId: true },
    });
    if (mapped) return mapped.userId;

    // An email match is NOT proof of ownership of the legacy account.
    const legacyAccount = await this.prisma.user.findFirst({
      where: { email: { equals: email, mode: 'insensitive' } },
      select: { id: true },
    });
    if (legacyAccount) {
      throw new ConflictException('LEGACY_ACCOUNT_LINK_REQUIRED');
    }

    // A random, never-disclosed password makes the transitional account
    // incompatible with legacy password login without an explicit migration.
    const passwordHash = await argon2.hash(randomBytes(32).toString('hex'));
    try {
      const created = await this.prisma.user.create({
        data: {
          email,
          passwordHash,
          socialIdentities: {
            create: identityKey,
          },
        },
        select: { id: true },
      });
      return created.id;
    } catch (error) {
      if ((error as { code?: string } | null)?.code === 'P2002') {
        // Another concurrent exchange may have inserted the same subject.
        const winner = await this.prisma.socialAuthIdentity.findUnique({
          where: { provider_subject: identityKey },
          select: { userId: true },
        });
        if (winner) return winner.userId;
        throw new ConflictException('LEGACY_ACCOUNT_LINK_REQUIRED');
      }
      throw error;
    }
  }
}
