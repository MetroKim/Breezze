import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { HomeService } from './home.service';
import { RecommendationsService } from '../recommendations/recommendations.service';

describe('HomeService listening history', () => {
  const prisma = {
    track: { findUnique: jest.fn() },
    listeningEvent: { findUnique: jest.fn() },
    recentlyPlayed: { findMany: jest.fn(), upsert: jest.fn() },
    favorite: { findMany: jest.fn() },
    $transaction: jest.fn(),
  };
  const tx = {
    recentlyPlayed: { upsert: jest.fn() },
    listeningEvent: { create: jest.fn() },
  };
  const recommendations = { forUser: jest.fn() };
  let service: HomeService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({ id: 'track-1' });
    prisma.recentlyPlayed.upsert.mockResolvedValue({ id: 'recent-1' });
    prisma.listeningEvent.findUnique.mockResolvedValue(null);
    prisma.$transaction.mockImplementation((callback: (value: typeof tx) => unknown) => callback(tx));
    tx.recentlyPlayed.upsert.mockResolvedValue({ id: 'recent-1' });
    tx.listeningEvent.create.mockResolvedValue({ id: 'event-1' });
    recommendations.forUser.mockResolvedValue([]);
    service = new HomeService(
      prisma as unknown as PrismaService,
      recommendations as unknown as RecommendationsService,
    );
  });

  it('syncs recent history without counting an unqualified listening event', async () => {
    await expect(service.recordRecent('user-1', 'track-1'))
      .resolves.toEqual({ recorded: true });

    expect(prisma.recentlyPlayed.upsert).toHaveBeenCalledWith({
      where: { userId_trackId: { userId: 'user-1', trackId: 'track-1' } },
      create: { userId: 'user-1', trackId: 'track-1' },
      update: { playedAt: expect.any(Date) },
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(tx.listeningEvent.create).not.toHaveBeenCalled();
  });

  it('records an event and recent history atomically using the supplied event ID', async () => {
    await expect(service.recordPlay('user-1', 'event-1', 'track-1', 45_000))
      .resolves.toEqual({ recorded: true, duplicate: false });

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.listeningEvent.create).toHaveBeenCalledWith({
      data: { id: 'event-1', userId: 'user-1', trackId: 'track-1', playedMs: 45_000 },
    });
    expect(tx.recentlyPlayed.upsert).toHaveBeenCalledWith({
      where: { userId_trackId: { userId: 'user-1', trackId: 'track-1' } },
      create: { userId: 'user-1', trackId: 'track-1' },
      update: { playedAt: expect.any(Date) },
    });
  });

  it('returns an identical retry without updating recent history again', async () => {
    prisma.listeningEvent.findUnique.mockResolvedValue({
      userId: 'user-1', trackId: 'track-1', playedMs: 45_000,
    });
    await expect(service.recordPlay('user-1', 'event-1', 'track-1', 45_000))
      .resolves.toEqual({ recorded: true, duplicate: true });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects event ID reuse for a different user, track, or duration', async () => {
    prisma.listeningEvent.findUnique.mockResolvedValue({
      userId: 'another-user', trackId: 'track-1', playedMs: 45_000,
    });
    await expect(service.recordPlay('user-1', 'event-1', 'track-1', 45_000))
      .rejects.toBeInstanceOf(ConflictException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects non-existent canonical tracks', async () => {
    prisma.track.findUnique.mockResolvedValue(null);
    await expect(service.recordPlay('user-1', 'event-1', 'missing-track', 45_000))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('does not count plays below the 30-second threshold', async () => {
    await expect(service.recordPlay('user-1', 'event-1', 'track-1', 29_999))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('recovers a concurrent duplicate insert only for an identical persisted event', async () => {
    prisma.$transaction.mockRejectedValue({ code: 'P2002' });
    prisma.listeningEvent.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ userId: 'user-1', trackId: 'track-1', playedMs: 45_000 });
    await expect(service.recordPlay('user-1', 'event-1', 'track-1', 45_000))
      .resolves.toEqual({ recorded: true, duplicate: true });
  });
});

describe('HomeService personalized feed integration', () => {
  const prisma = {
    recentlyPlayed: { findMany: jest.fn().mockResolvedValue([]) },
    favorite: { findMany: jest.fn().mockResolvedValue([]) },
  };
  const recommendations = { forUser: jest.fn() };

  it('includes recommendation output as a personalized home shelf', async () => {
    recommendations.forUser.mockResolvedValue([
      { trackId: 'recommended-1', reason: 'Because you listen to this artist' },
      { trackId: 'recommended-2', reason: 'Popular on Breezze' },
    ]);
    const service = new HomeService(
      prisma as unknown as PrismaService,
      recommendations as unknown as RecommendationsService,
    );
    await expect(service.feed('user-1', 'TZ')).resolves.toEqual([{
      sectionType: 'personalized',
      title: 'Made for You',
      layout: 'rail',
      trackIds: ['recommended-1', 'recommended-2'],
    }]);
    expect(recommendations.forUser).toHaveBeenCalledWith('user-1', 'TZ');
  });
});
