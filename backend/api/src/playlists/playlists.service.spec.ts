import { NotFoundException } from '@nestjs/common';
import { PlaylistsService } from './playlists.service';

describe('PlaylistsService tenant isolation', () => {
  const prisma = {
    playlist: {
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    track: { findUnique: jest.fn() },
    playlistItem: {
      count: jest.fn(),
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
  };

  let service: PlaylistsService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({ id: 'track-1' });
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

  it('rejects adding a track that is not in the canonical catalog', async () => {
    prisma.playlist.findFirst.mockResolvedValue({ id: 'playlist-a', userId: 'user-a' });
    prisma.track.findUnique.mockResolvedValue(null);

    await expect(service.addTrack('user-a', 'playlist-a', 'missing-track'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlistItem.count).not.toHaveBeenCalled();
    expect(prisma.playlistItem.create).not.toHaveBeenCalled();
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

  it('renames only a playlist owned by the caller', async () => {
    prisma.playlist.updateMany.mockResolvedValue({ count: 1 });
    prisma.playlist.findFirst.mockResolvedValue({ id: 'playlist-a', name: 'Renamed' });

    await expect(service.rename('user-a', 'playlist-a', 'Renamed'))
      .resolves.toEqual({ id: 'playlist-a', name: 'Renamed' });
    expect(prisma.playlist.updateMany).toHaveBeenCalledWith({
      where: { id: 'playlist-a', userId: 'user-a' },
      data: { name: 'Renamed' },
    });
  });

  it('does not rename another account playlist', async () => {
    prisma.playlist.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.rename('user-a', 'playlist-b', 'Stolen'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlist.findFirst).not.toHaveBeenCalled();
  });

  it('deletes only an owned playlist', async () => {
    prisma.playlist.deleteMany.mockResolvedValue({ count: 1 });
    await expect(service.delete('user-a', 'playlist-a'))
      .resolves.toEqual({ deleted: true });
    expect(prisma.playlist.deleteMany).toHaveBeenCalledWith({
      where: { id: 'playlist-a', userId: 'user-a' },
    });
  });

  it('does not delete another account playlist', async () => {
    prisma.playlist.deleteMany.mockResolvedValue({ count: 0 });
    await expect(service.delete('user-a', 'playlist-b'))
      .rejects.toBeInstanceOf(NotFoundException);
  });
});
