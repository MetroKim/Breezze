import { BadRequestException } from '@nestjs/common';
import { LibraryService } from './library.service';

describe('Saved catalog albums: owner isolation and rights boundaries', () => {
  const prisma = {
    userSavedCatalogAlbum: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
      upsert: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
  const service = new LibraryService(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('lists only account-owned catalog albums with a bounded response', async () => {
    prisma.userSavedCatalogAlbum.findMany.mockResolvedValue([]);
    await expect(service.listSavedAlbums('user-a')).resolves.toEqual({
      items: [], nextCursor: null,
    });
    expect(prisma.userSavedCatalogAlbum.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId: 'user-a', source: 'deezer' },
        take: 101,
      }),
    );
  });

  it('rejects a cursor not owned by the signed-in user', async () => {
    prisma.userSavedCatalogAlbum.findFirst.mockResolvedValue(null);
    await expect(service.listSavedAlbums('user-b', 'album-from-user-a'))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.userSavedCatalogAlbum.findFirst).toHaveBeenCalledWith({
      where: { userId: 'user-b', id: 'album-from-user-a', source: 'deezer' },
      select: { id: true },
    });
    expect(prisma.userSavedCatalogAlbum.findMany).not.toHaveBeenCalled();
  });

  it('returns pagination cursor without exposing extra records', async () => {
    const albums = Array.from({ length: 101 }, (_, i) => ({
      id: 'bookmark-' + i, title: 'Album ' + i,
    }));
    prisma.userSavedCatalogAlbum.findMany.mockResolvedValue(albums);
    const result = await service.listSavedAlbums('user-a');
    expect(result.items).toHaveLength(100);
    expect(result.nextCursor).toBe('bookmark-99');
  });

  it('upserts by the authenticated user + source + album identity', async () => {
    prisma.userSavedCatalogAlbum.upsert.mockResolvedValue({
      externalAlbumId: '123', title: 'Album',
    });
    await service.upsertSavedAlbum('user-a', {
      externalAlbumId: '123',
      title: ' Album ',
      artist: 'Artist',
      genres: ['Afrobeats', 'Afrobeats', 'Dance'],
      isCompilation: true,
      artworkUrl: 'https://cdn-images.dzcdn.net/images/cover/abcdef/250x250-000000-80-0-0.jpg',
      catalogUrl: 'https://www.deezer.com/album/123',
    });
    expect(prisma.userSavedCatalogAlbum.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          userId_source_externalAlbumId: {
            userId: 'user-a',
            source: 'deezer',
            externalAlbumId: '123',
          },
        },
        create: expect.objectContaining({
          userId: 'user-a',
          title: 'Album',
          genres: ['Afrobeats', 'Dance'],
          isCompilation: true,
        }),
      }),
    );
  });

  it('preserves pin status on unrelated metadata updates', async () => {
    prisma.userSavedCatalogAlbum.upsert.mockResolvedValue({ externalAlbumId: '123' });
    await service.upsertSavedAlbum('user-a', {
      externalAlbumId: '123', title: 'Album', artist: 'Artist',
    });
    expect(prisma.userSavedCatalogAlbum.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ isPinned: false }),
        update: expect.not.objectContaining({ isPinned: expect.anything() }),
      }),
    );
    await service.upsertSavedAlbum('user-a', {
      externalAlbumId: '123', title: 'Album', artist: 'Artist', isPinned: true,
    });
    expect(prisma.userSavedCatalogAlbum.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ isPinned: true }),
        update: expect.objectContaining({ isPinned: true }),
      }),
    );
    await service.upsertSavedAlbum('user-a', {
      externalAlbumId: '123', title: 'Album', artist: 'Artist', isPinned: false,
    });
    expect(prisma.userSavedCatalogAlbum.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({ update: expect.objectContaining({ isPinned: false }) }),
    );
  });

  it('rejects untrusted catalog URLs without any DB write', async () => {
    await expect(service.upsertSavedAlbum('user-a', {
      externalAlbumId: '123',
      title: 'Album',
      artist: 'Artist',
      catalogUrl: 'http://localhost:8080/admin',
    })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.userSavedCatalogAlbum.upsert).not.toHaveBeenCalled();
  });

  it('deletes idempotently under the authenticated user and fixed source', async () => {
    prisma.userSavedCatalogAlbum.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.removeSavedAlbum('user-b', '123'))
      .resolves.toEqual({ removed: true });
    expect(prisma.userSavedCatalogAlbum.deleteMany).toHaveBeenCalledWith({
      where: {
        userId: 'user-b',
        source: 'deezer',
        externalAlbumId: '123',
      },
    });
  });

  it('refuses invalid album IDs', async () => {
    await expect(service.removeSavedAlbum('user-a', '../admin'))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.userSavedCatalogAlbum.deleteMany).not.toHaveBeenCalled();
  });
});
