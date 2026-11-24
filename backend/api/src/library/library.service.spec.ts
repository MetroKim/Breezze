import { NotFoundException } from '@nestjs/common';
import { LibraryService } from './library.service';

describe('LibraryService tenant isolation', () => {
  const prisma = {
    userFollowedArtist: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      upsert: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    track: { findUnique: jest.fn() },
    favorite: {
      findMany: jest.fn(),
      upsert: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
  let service: LibraryService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({ id: 'track-1' });
    service = new LibraryService(prisma as any);
  });

  it('owner-scoped artist pin requires a followed record', async () => {
    prisma.userFollowedArtist.updateMany.mockResolvedValueOnce({ count: 0 })
      .mockResolvedValueOnce({ count: 1 });
    await expect(service.setArtistPinned('other-user', 'apple:10', true))
      .rejects.toBeInstanceOf(NotFoundException);
    await expect(service.setArtistPinned('user-a', 'apple:10', true))
      .resolves.toEqual({ following: true, isPinned: true });
    expect(prisma.userFollowedArtist.updateMany).toHaveBeenLastCalledWith({
      where: { userId: 'user-a', artistKey: 'apple:10' },
      data: { isPinned: true },
    });
  });

  it('lists followed artists using the authenticated account only', async () => {
    prisma.userFollowedArtist.findMany.mockResolvedValue([]);
    await expect(service.listFollowedArtists('user-a'))
      .resolves.toEqual({ items: [] });
    expect(prisma.userFollowedArtist.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      orderBy: [
        { isPinned: 'desc' }, { followedAt: 'desc' }, { artistKey: 'asc' },
      ],
      select: {
        artistKey: true, displayName: true, isPinned: true, followedAt: true,
      },
    });
  });

  it('lists favorites for the authenticated user only', async () => {
    prisma.favorite.findMany.mockResolvedValue([]);
    await service.listFavorites('user-a');
    expect(prisma.favorite.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        trackId: true,
        createdAt: true,
        track: {
          select: {
            id: true,
            title: true,
            duration: true,
            artist: { select: { name: true } },
          },
        },
      },
    });
  });

  it('adds a favorite under the authenticated user composite key', async () => {
    prisma.favorite.upsert.mockResolvedValue({ id: 'fav-1' });
    await service.addFavorite('user-a', 'track-1');
    expect(prisma.track.findUnique).toHaveBeenCalledWith({
      where: { id: 'track-1' },
      select: { id: true },
    });
    expect(prisma.favorite.upsert).toHaveBeenCalledWith({
      where: { userId_trackId: { userId: 'user-a', trackId: 'track-1' } },
      create: { userId: 'user-a', trackId: 'track-1' },
      update: {},
    });
  });

  it('rejects favorites for tracks outside the canonical catalog', async () => {
    prisma.track.findUnique.mockResolvedValue(null);
    await expect(service.addFavorite('user-a', 'missing-track'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.favorite.upsert).not.toHaveBeenCalled();
  });

  it('removes a favorite only from the authenticated user library', async () => {
    prisma.favorite.deleteMany.mockResolvedValue({ count: 1 });
    await service.removeFavorite('user-a', 'track-1');
    expect(prisma.favorite.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-a', trackId: 'track-1' },
    });
  });
});
