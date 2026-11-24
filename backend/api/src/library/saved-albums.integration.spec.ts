import { randomUUID } from 'node:crypto';
import { BadRequestException } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { LibraryService } from './library.service';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

describeIntegration('Saved albums PostgreSQL ownership and idempotency', () => {
  const userIds: string[] = [];
  let service: LibraryService;

  beforeAll(async () => {
    await prisma.$connect();
    service = new LibraryService(prisma as unknown as PrismaService);
  });

  afterAll(async () => {
    if (userIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    }
    await prisma.$disconnect();
  });

  async function createUser() {
    const row = await prisma.user.create({
      data: {
        email: `album-sync-${randomUUID()}@integration.invalid`,
        passwordHash: 'integration-only',
      },
      select: { id: true },
    });
    userIds.push(row.id);
    return row.id;
  }

  it('scopes artist follows to the listener and handles repeated taps', async () => {
    const listener = await createUser();
    const other = await createUser();
    const key = 'apple:21';
    await Promise.all([service.setFollowing(listener, key, true),
      service.setFollowing(listener, key, true)]);
    expect(await service.artistStatus(listener, key)).toEqual({ following: true });
    expect(await service.artistStatus(other, key)).toEqual({ following: false });
    await service.setFollowing(other, key, false);
    expect(await service.artistStatus(listener, key)).toEqual({ following: true });
    await service.setFollowing(listener, key, false);
    expect(await service.artistStatus(listener, key)).toEqual({ following: false });
  });

  it('keeps the same public album ID separate for two users', async () => {
    const a = await createUser();
    const b = await createUser();
    const albumId = '123456';

    await service.upsertSavedAlbum(a, {
      externalAlbumId: albumId, title: 'Library A', artist: 'Artist A',
      genres: ['Jazz'], isCompilation: false,
    });
    await service.upsertSavedAlbum(b, {
      externalAlbumId: albumId, title: 'Library B', artist: 'Artist B',
      genres: ['Dance'], isCompilation: true,
    });

    const aList = await service.listSavedAlbums(a);
    const bList = await service.listSavedAlbums(b);
    expect(aList.items).toHaveLength(1);
    expect(bList.items).toHaveLength(1);
    expect(aList.items[0].title).toBe('Library A');
    expect(bList.items[0].title).toBe('Library B');
    expect(aList.items[0].id).not.toBe(bList.items[0].id);

    await service.removeSavedAlbum(a, albumId);
    expect((await service.listSavedAlbums(a)).items).toHaveLength(0);
    expect((await service.listSavedAlbums(b)).items).toHaveLength(1);
  });

  it('pins only the owner album and syncs pin and unpin across sessions',
      async () => {
    const a = await createUser();
    const b = await createUser();
    for (const id of ['101', '202']) {
      await service.upsertSavedAlbum(a, {
        externalAlbumId: id, title: 'Album ' + id, artist: 'Artist',
      });
    }
    await service.upsertSavedAlbum(b, {
      externalAlbumId: '101', title: 'Other private copy', artist: 'Artist',
    });
    await service.upsertSavedAlbum(a, {
      externalAlbumId: '101', title: 'Album 101', artist: 'Artist', isPinned: true,
    });
    const own = (await service.listSavedAlbums(a)).items;
    expect(own.map(x => x.externalAlbumId)).toEqual(['101', '202']);
    expect(own.map(x => x.isPinned)).toEqual([true, false]);
    expect((await service.listSavedAlbums(b)).items[0].isPinned).toBe(false);
    await service.upsertSavedAlbum(a, {
      externalAlbumId: '101', title: 'Changed title', artist: 'Artist',
    });
    expect((await service.listSavedAlbums(a)).items[0].isPinned).toBe(true);
    await service.upsertSavedAlbum(a, {
      externalAlbumId: '101', title: 'Changed title', artist: 'Artist', isPinned: false,
    });
    expect((await service.listSavedAlbums(a)).items.every(x => !x.isPinned)).toBe(true);
    expect((await service.listSavedAlbums(b)).items[0].isPinned).toBe(false);
  });

  it('concurrent upserts of one album are idempotent', async () => {
    const userId = await createUser();
    const externalAlbumId = '777888';
    await Promise.all(Array.from({ length: 5 }, () =>
      service.upsertSavedAlbum(userId, {
        externalAlbumId, title: 'One album', artist: 'Artist',
      })));
    const count = await prisma.userSavedCatalogAlbum.count({
      where: { userId, externalAlbumId },
    });
    expect(count).toBe(1);
  });

  it('does not accept another user\'s pagination cursor', async () => {
    const userA = await createUser();
    const userB = await createUser();
    const saved = await service.upsertSavedAlbum(userB, {
      externalAlbumId: '55555', title: 'Album B', artist: 'Artist B',
    });
    await expect(service.listSavedAlbums(userA, saved.id))
      .rejects.toBeInstanceOf(BadRequestException);
  });

  it('deleting the user cascades to saved album bookmarks only', async () => {
    const userId = await createUser();
    await service.upsertSavedAlbum(userId, {
      externalAlbumId: '999999', title: 'Owned', artist: 'Artist',
    });
    await prisma.user.delete({ where: { id: userId } });
    userIds.splice(userIds.indexOf(userId), 1);
    expect(await prisma.userSavedCatalogAlbum.count({
      where: { userId },
    })).toBe(0);
  });
});
