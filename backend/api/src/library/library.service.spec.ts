import { NotFoundException } from '@nestjs/common';
import { LibraryService } from './library.service';

describe('LibraryService tenant isolation', () => {
  const prisma = {
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

  it('lists favorites for the authenticated user only', async () => {
    prisma.favorite.findMany.mockResolvedValue([]);
    await service.listFavorites('user-a');
    expect(prisma.favorite.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      orderBy: { createdAt: 'desc' },
      select: { id: true, trackId: true, createdAt: true },
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
