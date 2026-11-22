import { NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { HomeService } from './home.service';

describe('HomeService listening history', () => {
  const prisma = {
    track: { findUnique: jest.fn() },
    recentlyPlayed: { findMany: jest.fn() },
    favorite: { findMany: jest.fn() },
    $transaction: jest.fn(),
  };
  const tx = {
    recentlyPlayed: { upsert: jest.fn() },
    listeningEvent: { create: jest.fn() },
  };
  let service: HomeService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({ id: 'track-1' });
    prisma.$transaction.mockImplementation((callback: (value: typeof tx) => unknown) => callback(tx));
    tx.recentlyPlayed.upsert.mockResolvedValue({ id: 'recent-1' });
    tx.listeningEvent.create.mockResolvedValue({ id: 'event-1' });
    service = new HomeService(prisma as unknown as PrismaService);
  });

  it('records recent history and listening analytics atomically', async () => {
    await expect(service.recordPlay('user-1', 'track-1', 45_000))
      .resolves.toEqual({ recorded: true });

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.recentlyPlayed.upsert).toHaveBeenCalledWith({
      where: { userId_trackId: { userId: 'user-1', trackId: 'track-1' } },
      create: { userId: 'user-1', trackId: 'track-1' },
      update: { playedAt: expect.any(Date) },
    });
    expect(tx.listeningEvent.create).toHaveBeenCalledWith({
      data: { userId: 'user-1', trackId: 'track-1', playedMs: 45_000 },
    });
  });

  it('rejects non-existent canonical tracks', async () => {
    prisma.track.findUnique.mockResolvedValue(null);

    await expect(service.recordPlay('user-1', 'missing-track', 45_000))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('does not count plays below the 30-second threshold', async () => {
    await expect(service.recordPlay('user-1', 'track-1', 29_999))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});
