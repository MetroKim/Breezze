import { NotFoundException } from '@nestjs/common';
import { PlaylistsService } from './playlists.service';

describe('PlaylistsService tenant isolation and ordering', () => {
  const tx = {
    $queryRaw: jest.fn(),
    track: { findUnique: jest.fn() },
    playlistItem: {
      findFirst: jest.fn(),
      aggregate: jest.fn(),
      create: jest.fn(),
    },
  };
  const prisma = {
    $transaction: jest.fn(),
    playlist: {
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    playlistItem: { deleteMany: jest.fn() },
  };

  let service: PlaylistsService;

  beforeEach(() => {
    jest.clearAllMocks();
    tx.$queryRaw.mockResolvedValue([{ id: 'playlist-a' }]);
    tx.track.findUnique.mockResolvedValue({ id: 'track-1' });
    tx.playlistItem.findFirst.mockResolvedValue(null);
    tx.playlistItem.aggregate.mockResolvedValue({ _max: { position: 3 } });
    tx.playlistItem.create.mockResolvedValue({
      id: 'item-1',
      playlistId: 'playlist-a',
      trackId: 'track-1',
      position: 4,
    });
    prisma.$transaction.mockImplementation(
      (callback: (value: typeof tx) => unknown) => callback(tx),
    );
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
    tx.track.findUnique.mockResolvedValue(null);

    await expect(service.addTrack('user-a', 'playlist-a', 'missing-track'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(tx.playlistItem.aggregate).not.toHaveBeenCalled();
    expect(tx.playlistItem.create).not.toHaveBeenCalled();
  });

  it('does not mutate a playlist owned by another user', async () => {
    tx.$queryRaw.mockResolvedValue([]);

    await expect(service.addTrack('user-a', 'playlist-owned-by-b', 'track-1'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(tx.track.findUnique).not.toHaveBeenCalled();
    expect(tx.playlistItem.create).not.toHaveBeenCalled();
  });

  it('locks the owned playlist and appends after the highest position', async () => {
    await expect(service.addTrack('user-a', 'playlist-a', 'track-1'))
      .resolves.toMatchObject({ position: 4 });

    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    expect(tx.playlistItem.aggregate).toHaveBeenCalledWith({
      where: { playlistId: 'playlist-a' },
      _max: { position: true },
    });
    expect(tx.playlistItem.create).toHaveBeenCalledWith({
      data: { playlistId: 'playlist-a', trackId: 'track-1', position: 4 },
    });
  });

  it('does not create a duplicate when a client retries an add', async () => {
    const existing = { id: 'existing-item', playlistId: 'playlist-a', trackId: 'track-1', position: 2 };
    tx.playlistItem.findFirst.mockResolvedValue(existing);

    await expect(service.addTrack('user-a', 'playlist-a', 'track-1'))
      .resolves.toBe(existing);
    expect(tx.playlistItem.aggregate).not.toHaveBeenCalled();
    expect(tx.playlistItem.create).not.toHaveBeenCalled();
  });

  it('scopes playlist removal to an owned playlist', async () => {
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
