import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { AuthService } from './auth.service';
import { SupabaseExchangeService } from './supabase-exchange.service';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

describeIntegration('Auth session PostgreSQL integration', () => {
  const userIds: string[] = [];
  let service: AuthService;

  beforeAll(async () => {
    await prisma.$connect();
    service = new AuthService(
      prisma as unknown as PrismaService,
      { signAsync: jest.fn().mockResolvedValue('integration-access-token') } as never,
    );
  });

  afterAll(async () => {
    if (userIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    }
    await prisma.$disconnect();
  });

  async function createUser() {
    const user = await prisma.user.create({
      data: {
        email: `auth-session-${randomUUID()}@integration.invalid`,
        passwordHash: 'integration-only-not-a-real-password',
      },
      select: { id: true, email: true, displayName: true },
    });
    userIds.push(user.id);
    return user;
  }

  async function createRefreshToken(userId: string, familyId: string, rawToken = randomBytes(32).toString('hex')) {
    await prisma.refreshToken.create({
      data: {
        tokenHash: createHash('sha256').update(rawToken, 'utf8').digest('hex'),
        familyId,
        userId,
        expiresAt: new Date(Date.now() + 60_000),
      },
    });
    return rawToken;
  }

  it('rotates a refresh token once and revokes the family on concurrent replay', async () => {
    const user = await createUser();
    const familyId = randomUUID();
    const rawToken = await createRefreshToken(user.id, familyId);

    const attempts = await Promise.allSettled([
      service.refresh(rawToken),
      service.refresh(rawToken),
    ]);

    expect(attempts.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    expect(attempts.filter((result) => result.status === 'rejected')).toHaveLength(1);

    const family = await prisma.refreshToken.findMany({
      where: { familyId, userId: user.id },
    });
    expect(family.length).toBeGreaterThanOrEqual(1);
    expect(family.every((token) => token.revokedAt !== null)).toBe(true);
    expect(family.some((token) => token.tokenHash === createHash('sha256').update(rawToken, 'utf8').digest('hex'))).toBe(true);
    expect(family.every((token) => token.tokenHash !== rawToken)).toBe(true);
  });

  it('revokes only the selected user-owned session family', async () => {
    const user = await createUser();
    const selectedFamily = randomUUID();
    const otherFamily = randomUUID();
    await createRefreshToken(user.id, selectedFamily);
    await createRefreshToken(user.id, selectedFamily);
    await createRefreshToken(user.id, otherFamily);

    const selectedSession = await prisma.refreshToken.findFirstOrThrow({
      where: { userId: user.id, familyId: selectedFamily },
      select: { id: true },
    });
    await service.revokeSession(user.id, selectedSession.id);

    const rows = await prisma.refreshToken.findMany({ where: { userId: user.id } });
    expect(rows.filter((row) => row.familyId === selectedFamily).every((row) => row.revokedAt !== null)).toBe(true);
    expect(rows.filter((row) => row.familyId === otherFamily).every((row) => row.revokedAt === null)).toBe(true);
  });

  it('does not let one account revoke another account session', async () => {
    const owner = await createUser();
    const attacker = await createUser();
    const familyId = randomUUID();
    const token = await createRefreshToken(owner.id, familyId);
    const session = await prisma.refreshToken.findFirstOrThrow({
      where: { userId: owner.id, familyId },
      select: { id: true },
    });

    await expect(service.revokeSession(attacker.id, session.id)).rejects.toThrow('SESSION_NOT_FOUND');
    const stored = await prisma.refreshToken.findUniqueOrThrow({
      where: { tokenHash: createHash('sha256').update(token, 'utf8').digest('hex') },
    });
    expect(stored.revokedAt).toBeNull();
  });

  it('links an existing user without changing library ownership in PostgreSQL', async () => {
    const oldPassword = 'migration-legacy-password';
    const original = await prisma.user.create({
      data: {
        email: `link-${randomUUID()}@integration.invalid`,
        passwordHash: await argon2.hash(oldPassword),
        preference: {
          create: {
            genres: ['jazz'],
            favoriteArtists: ['Original Artist'],
            country: 'TZ',
          },
        },
      },
      select: { id: true, email: true },
    });
    userIds.push(original.id);
    const second = await prisma.user.create({
      data: {
        email: `link-other-${randomUUID()}@integration.invalid`,
        passwordHash: await argon2.hash('second-account-secret'),
      },
      select: { id: true, email: true },
    });
    userIds.push(second.id);

    const identityId = randomUUID();
    const oldUrl = process.env.SUPABASE_URL;
    const oldKey = process.env.SUPABASE_PUBLISHABLE_KEY;
    process.env.SUPABASE_URL = 'https://migration-test.supabase.co';
    process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_test';
    const fetchMock = jest.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({
        id: identityId,
        email: 'masked@privaterelay.appleid.com',
        email_confirmed_at: '2026-11-24T00:00:00Z',
      }), { status: 200 }),
    );
    const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJleGFtcGxlIn0.c2lnbmF0dXJl';
    try {
      const exchange = new SupabaseExchangeService(
        prisma as unknown as PrismaService,
        service,
      );
      const linked = await exchange.linkLegacy(token, original.email, oldPassword);
      expect(linked.user.id).toBe(original.id);

      const mapping = await prisma.socialAuthIdentity.findUniqueOrThrow({
        where: { provider_subject: {
          provider: 'supabase',
          subject: `migration-test.supabase.co:${identityId}`,
        } },
      });
      expect(mapping.userId).toBe(original.id);
      const library = await prisma.userPreference.findUniqueOrThrow({
        where: { userId: original.id },
      });
      expect(library.genres).toEqual(['jazz']);
      expect(library.favoriteArtists).toEqual(['Original Artist']);

      const signedIn = await exchange.exchange(token);
      expect(signedIn.user.id).toBe(original.id);

      await expect(exchange.linkLegacy(token, second.email, 'second-account-secret'))
        .rejects.toThrow('SUPABASE_IDENTITY_ALREADY_LINKED');
      const stillOwned = await prisma.user.findUniqueOrThrow({ where: { id: second.id } });
      expect(stillOwned.email).toBe(second.email);
    } finally {
      fetchMock.mockRestore();
      if (oldUrl === undefined) delete process.env.SUPABASE_URL;
      else process.env.SUPABASE_URL = oldUrl;
      if (oldKey === undefined) delete process.env.SUPABASE_PUBLISHABLE_KEY;
      else process.env.SUPABASE_PUBLISHABLE_KEY = oldKey;
    }
  });
});
