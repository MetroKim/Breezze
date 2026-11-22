import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { RecommendationsService } from '../recommendations/recommendations.service';
import { HomeService } from './home.service';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

describeIntegration('Home play-event PostgreSQL integration', () => {
  const userIds: string[] = [];
  const trackIds: string[] = [];
  const artistIds: string[] = [];
  let service: HomeService;

  beforeAll(async () => {
    await prisma.$connect();
    service = new HomeService(
      prisma as unknown as PrismaService,
      {} as RecommendationsService,
    );
  });

  afterAll(async () => {
    if (userIds.length) await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    if (trackIds.length) await prisma.track.deleteMany({ where: { id: { in: trackIds } } });
    if (artistIds.length) await prisma.artist.deleteMany({ where: { id: { in: artistIds } } });
    await prisma.$disconnect();
  });

  async function fixtures() {
    const suffix = randomUUID();
    const user = await prisma.user.create({
      data: {
        email: `home-play-${suffix}@integration.invalid`,
        passwordHash: 'integration-only-not-a-real-password',
      },
      select: { id: true },
    });
    userIds.push(user.id);

    const artist = await prisma.artist.create({
      data: { name: `Integration Artist ${suffix}` },
      select: { id: true },
    });
    artistIds.push(artist.id);

    const track = await prisma.track.create({
      data: {
        title: 'Integration Track',
        artistId: artist.id,
        duration: 180,
      },
      select: { id: true },
    });
    trackIds.push(track.id);
    return { userId: user.id, trackId: track.id };
  }

  it('persists one event and one recent-play row for concurrent identical retries', async () => {
    const { userId, trackId } = await fixtures();
    const eventId = randomUUID();

    const results = await Promise.all([
      service.recordPlay(userId, eventId, trackId, 45_000),
      service.recordPlay(userId, eventId, trackId, 45_000),
    ]);

    expect(results.map((result) => result.duplicate).sort()).toEqual([false, true]);
    expect(await prisma.listeningEvent.count({ where: { id: eventId } })).toBe(1);
    expect(await prisma.recentlyPlayed.count({ where: { userId, trackId } })).toBe(1);
  });

  it('rejects concurrent reuse of one event ID for different play data', async () => {
    const { userId, trackId } = await fixtures();
    const eventId = randomUUID();

    const results = await Promise.allSettled([
      service.recordPlay(userId, eventId, trackId, 30_000),
      service.recordPlay(userId, eventId, trackId, 31_000),
    ]);

    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    const rejected = results.find((result) => result.status === 'rejected') as PromiseRejectedResult;
    expect(rejected.reason.getStatus()).toBe(409);
    expect(await prisma.listeningEvent.count({ where: { id: eventId } })).toBe(1);
  });
});
