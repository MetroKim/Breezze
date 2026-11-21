import { NotFoundException } from '@nestjs/common';
import { PlaylistsService } from './playlists.service';

describe('PlaylistsService tenant isolation', () => {
  const prisma = {
    playlist: {
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
    },
    playlistItem: {
      count: jest.fn(),
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
  };

  let service: PlaylistsService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new PlaylistsService(prisma as any);
  });

  it('lists only playlists owned by the authenticated user', async () => {
    prisma.playlist.findMany.mockResolvedValue([]);
    await service.list('user-a');
    expect(prisma.playlist.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      orderBy: { createdAt: 'desc' },
    });
  });

  it('does not disclose another user playlist', async () => {
    prisma.playlist.findFirst.mockResolvedValue(null);
    await expect(service.get('user-a', 'playlist-owned-by-b'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlist.findFirst).toHaveBeenCalledWith({
      where: { id: 'playlist-owned-by-b', userId: 'user-a' },
      include: { items: { orderBy: { position: 'asc' } } },
    });
  });

  it('does not mutate a playlist owned by another user', async () => {
    prisma.playlist.findFirst.mockResolvedValue(null);
    await expect(service.addTrack('user-a', 'playlist-owned-by-b', 'track-1'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlistItem.count).not.toHaveBeenCalled();
    expect(prisma.playlistItem.create).not.toHaveBeenCalled();
  });

  it('scopes playlist deletion to an owned playlist before removing tracks', async () => {
    prisma.playlist.findFirst.mockResolvedValue(null);
    await expect(service.removeTrack('user-a', 'playlist-owned-by-b', 'track-1'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlistItem.deleteMany).not.toHaveBeenCalled();
  });
});
