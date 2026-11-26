import { NotFoundException } from '@nestjs/common';
import { PlaylistsService } from './playlists.service';

describe('PlaylistsService tenant isolation and ordering', () => {
  const tx = {
    $queryRaw: jest.fn(),
    track: { findUnique: jest.fn() },
    playlistItem: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
      aggregate: jest.fn(),
      create: jest.fn(),
      updateMany: jest.fn(),
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
      orderBy: [{ isPinned: 'desc' }, { createdAt: 'desc' }],
      include: {
        items: {
          orderBy: { position: 'asc' },
          include: {
            track: { include: { artist: true, album: true } },
          },
        },
      },
    });
  });

  it('saves a real small PNG thumbnail only on an owned playlist', async () => {
    const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC' +
      'AAAAC0lEQVR42mP8/x8AAwMCAO+/+5AAAAAASUVORK5CYII=',
      'base64',
    ).toString('base64');
    prisma.playlist.updateMany.mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 });
    await expect(service.setCover('user-a', 'playlist-a', png))
      .resolves.toEqual({ id: 'playlist-a', coverPngBase64: png });
    expect(prisma.playlist.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-a', id: 'playlist-a' },
      data: { coverPngBase64: png },
    });
    await expect(service.setCover('user-b', 'playlist-a', png))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects fake PNG/base64 and oversized cover before database writes', async () => {
    await expect(service.setCover('user-a', 'playlist-a', 'YWJj'))
      .rejects.toThrow('PLAYLIST_COVER_INVALID_PNG');
    await expect(service.setCover('user-a', 'playlist-a', '*'))
      .rejects.toThrow('PLAYLIST_COVER_INVALID_ENCODING');
    await expect(service.setCover('user-a', 'playlist-a', 'A'.repeat(350001)))
      .rejects.toThrow('PLAYLIST_COVER_INVALID_ENCODING');
    expect(prisma.playlist.updateMany).not.toHaveBeenCalled();
  });

  it('clears the cover only for its owner', async () => {
    prisma.playlist.updateMany.mockResolvedValue({ count: 1 });
    await expect(service.setCover('user-a', 'playlist-a', null))
      .resolves.toEqual({ id: 'playlist-a', coverPngBase64: null });
    expect(prisma.playlist.updateMany).toHaveBeenCalledWith({
      where: { id: 'playlist-a', userId: 'user-a' },
      data: { coverPngBase64: null },
    });
  });

  it('pins only an owned playlist and rejects cross-account changes',
      async () => {
    prisma.playlist.updateMany.mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 });
    prisma.playlist.findFirst.mockResolvedValue({
      id: 'playlist-a', userId: 'user-a', isPinned: true,
    });
    await expect(service.setPinned('user-a', 'playlist-a', true))
      .resolves.toMatchObject({ isPinned: true });
    expect(prisma.playlist.updateMany).toHaveBeenCalledWith({
      where: { id: 'playlist-a', userId: 'user-a' },
      data: { isPinned: true },
    });
    await expect(service.setPinned('user-b', 'playlist-a', false))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlist.findFirst).toHaveBeenCalledTimes(1);
  });

  it('creates with a client UUID for idempotent offline replay', async () => {
    const id = '11111111-1111-4111-8111-111111111111';
    prisma.playlist.create.mockResolvedValue({ id, userId: 'user-a', name: 'Offline mix' });
    await expect(service.create('user-a', 'Offline mix', id))
      .resolves.toEqual({ id, userId: 'user-a', name: 'Offline mix' });
    expect(prisma.playlist.create).toHaveBeenCalledWith({
      data: { id, userId: 'user-a', name: 'Offline mix' },
    });
  });

  it('replays an already-created owned playlist without overwriting its name', async () => {
    const id = '11111111-1111-4111-8111-111111111111';
    prisma.playlist.create.mockRejectedValue({ code: 'P2002' });
    prisma.playlist.findFirst.mockResolvedValue({ id, userId: 'user-a', name: 'Renamed elsewhere' });
    const result = await service.create('user-a', 'Older offline name', id);
    expect(result.name).toBe('Renamed elsewhere');
    expect(prisma.playlist.findFirst).toHaveBeenCalledWith({ where: { id, userId: 'user-a' } });
  });

  it('rejects a client UUID already owned by a different account', async () => {
    const id = '11111111-1111-4111-8111-111111111111';
    prisma.playlist.create.mockRejectedValue({ code: 'P2002' });
    prisma.playlist.findFirst.mockResolvedValue(null);
    await expect(service.create('user-b', 'Hijack attempt', id))
      .rejects.toThrow('PLAYLIST_ID_CONFLICT');
  });

  it('does not disclose another user playlist', async () => {
    prisma.playlist.findFirst.mockResolvedValue(null);
    await expect(service.get('user-a', 'playlist-owned-by-b'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.playlist.findFirst).toHaveBeenCalledWith({
      where: { id: 'playlist-owned-by-b', userId: 'user-a' },
      include: {
        items: {
          orderBy: { position: 'asc' },
          include: {
            track: {
              include: { artist: true, album: true },
            },
          },
        },
      },
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

  it('reorders only the exact current membership of an owned playlist', async () => {
    tx.playlistItem.findMany.mockResolvedValue([
      { trackId: 'track-1' },
      { trackId: 'track-2' },
      { trackId: 'track-3' },
    ]);
    tx.playlistItem.updateMany.mockResolvedValue({ count: 1 });

    await expect(service.reorderTracks(
      'user-a',
      'playlist-a',
      ['track-3', 'track-1', 'track-2'],
    )).resolves.toEqual({ reordered: true, count: 3 });

    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    expect(tx.playlistItem.updateMany).toHaveBeenNthCalledWith(1, {
      where: { playlistId: 'playlist-a', trackId: 'track-3' },
      data: { position: 0 },
    });
    expect(tx.playlistItem.updateMany).toHaveBeenNthCalledWith(2, {
      where: { playlistId: 'playlist-a', trackId: 'track-1' },
      data: { position: 1 },
    });
    expect(tx.playlistItem.updateMany).toHaveBeenNthCalledWith(3, {
      where: { playlistId: 'playlist-a', trackId: 'track-2' },
      data: { position: 2 },
    });
  });

  it('rejects reorder requests that omit or inject playlist items', async () => {
    tx.playlistItem.findMany.mockResolvedValue([
      { trackId: 'track-1' },
      { trackId: 'track-2' },
    ]);

    await expect(service.reorderTracks(
      'user-a',
      'playlist-a',
      ['track-1', 'track-from-another-playlist'],
    )).rejects.toThrow('PLAYLIST_ORDER_MISMATCH');
    expect(tx.playlistItem.updateMany).not.toHaveBeenCalled();
  });

  it('does not reorder another account playlist', async () => {
    tx.$queryRaw.mockResolvedValue([]);

    await expect(service.reorderTracks(
      'user-a',
      'playlist-owned-by-b',
      ['track-1'],
    )).rejects.toBeInstanceOf(NotFoundException);
    expect(tx.playlistItem.findMany).not.toHaveBeenCalled();
    expect(tx.playlistItem.updateMany).not.toHaveBeenCalled();
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
