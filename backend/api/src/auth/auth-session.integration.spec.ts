import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { AuthService } from './auth.service';
import { SupabaseExchangeService } from './supabase-exchange.service';

import { LibraryService } from '../library/library.service';
import { PlaylistsService } from '../playlists/playlists.service';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

describeIntegration('Auth session PostgreSQL integration', () => {
  const userIds: string[] = [];
  const catalogTrackIds: string[] = [];
  const catalogArtistIds: string[] = [];
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
    // Keep fixtures isolated; remove catalog rows only after their user-owned
    // favorites, playlist items, and play history have cascaded away.
    if (catalogTrackIds.length) {
      await prisma.track.deleteMany({ where: { id: { in: catalogTrackIds } } });
    }
    if (catalogArtistIds.length) {
      await prisma.artist.deleteMany({ where: { id: { in: catalogArtistIds } } });
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

  it('replays offline playlist UUIDs idempotently and enforces account ownership', async () => {
    const owner = await createUser();
    const stranger = await createUser();
    const playlistId = randomUUID();
    const playlists = new PlaylistsService(prisma as unknown as PrismaService);

    const created = await playlists.create(owner.id, 'Offline music', playlistId);
    const retried = await playlists.create(owner.id, 'Old retry name', playlistId);
    expect(retried.id).toBe(created.id);
    expect(retried.name).toBe('Offline music');

    await expect(playlists.create(stranger.id, 'Foreign claim', playlistId))
      .rejects.toThrow('PLAYLIST_ID_CONFLICT');
    expect(await playlists.list(stranger.id)).toEqual([]);
    await expect(playlists.get(stranger.id, playlistId))
      .rejects.toThrow('PLAYLIST_NOT_FOUND');

    await playlists.rename(owner.id, playlistId, 'Synced name');
    const ownerRows = await playlists.list(owner.id);
    expect(ownerRows).toHaveLength(1);
    expect(ownerRows[0].name).toBe('Synced name');

    await playlists.delete(owner.id, playlistId);
    expect(await playlists.list(owner.id)).toEqual([]);
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

    // Existing listener data must continue to resolve to the SAME user ID
    // after linking, while a different listener's API queries stay isolated.
    const artist = await prisma.artist.create({
      data: { name: `Migration Artist ${randomUUID()}` },
      select: { id: true },
    });
    catalogArtistIds.push(artist.id);
    const track = await prisma.track.create({
      data: {
        title: 'Original saved track',
        duration: 196,
        artistId: artist.id,
      },
      select: { id: true },
    });
    catalogTrackIds.push(track.id);
    const playlist = await prisma.playlist.create({
      data: {
        userId: original.id,
        name: 'Original playlist',
        items: { create: [{ trackId: track.id, position: 0 }] },
      },
      select: { id: true },
    });
    await prisma.favorite.create({ data: {
      userId: original.id, trackId: track.id,
    } });
    await prisma.recentlyPlayed.create({ data: {
      userId: original.id, trackId: track.id,
    } });
    await prisma.downloadRecord.create({ data: {
      userId: original.id, trackId: track.id,
      status: 'active',
    } });
    await prisma.listeningEvent.create({ data: {
      userId: original.id, trackId: track.id,
      playedMs: 30_000,
      isServerVerified: true,
    } });

    const identityId = randomUUID();
    const oldUrl = process.env.SUPABASE_URL;
    const oldKey = process.env.SUPABASE_PUBLISHABLE_KEY;
    process.env.SUPABASE_URL = 'https://migration-test.supabase.co';
    process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_test';
    const fetchMock = jest.spyOn(globalThis, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({
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
      // Even a leaked Breezze refresh token cannot renew Supabase sessions.
      await expect(service.refresh(linked.refreshToken))
        .rejects.toThrow('SUPABASE_REFRESH_REQUIRED');

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

      const playlists = new PlaylistsService(prisma as unknown as PrismaService);
      const favorites = new LibraryService(prisma as unknown as PrismaService);
      const originalPlaylists = await playlists.list(original.id);
      expect(originalPlaylists.map((row) => row.id)).toContain(playlist.id);

      const originalPlaylist = await playlists.get(original.id, playlist.id);
      expect(originalPlaylist.items.map((item) => item.trackId))
        .toEqual([track.id]);
      expect((await favorites.listFavorites(original.id))
        .map((row) => row.trackId)).toContain(track.id);

      expect(await playlists.list(second.id)).toEqual([]);
      await expect(playlists.get(second.id, playlist.id))
        .rejects.toThrow('PLAYLIST_NOT_FOUND');
      expect(await favorites.listFavorites(second.id)).toEqual([]);

      const recent = await prisma.recentlyPlayed.findFirstOrThrow({
        where: { userId: original.id, trackId: track.id },
      });
      expect(recent.userId).toBe(original.id);
      expect(await prisma.recentlyPlayed.count({
        where: { userId: second.id },
      })).toBe(0);

      const download = await prisma.downloadRecord.findFirstOrThrow({
        where: { userId: original.id, trackId: track.id },
      });
      expect(download.userId).toBe(original.id);
      expect(await prisma.downloadRecord.count({
        where: { userId: second.id },
      })).toBe(0);

      const replay = await prisma.listeningEvent.findFirstOrThrow({
        where: { userId: original.id, trackId: track.id },
      });
      expect(replay.playedMs).toBe(30_000);
      expect(await prisma.listeningEvent.count({
        where: { userId: second.id },
      })).toBe(0);

      const signedIn = await exchange.exchange(token);
      expect(signedIn.user.id).toBe(original.id);
      expect((await playlists.list(signedIn.user.id))[0].id).toBe(playlist.id);

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
