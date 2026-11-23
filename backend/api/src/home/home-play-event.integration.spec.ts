import { randomUUID } from 'node:crypto';
import { GoneException } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { RecommendationsService } from '../recommendations/recommendations.service';
import { HomeService } from './home.service';
import { HomeController } from './home.controller';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

describeIntegration('Home history PostgreSQL integration', () => {
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
        email: `home-history-${suffix}@integration.invalid`,
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

  it('rejects client-asserted qualified plays and keeps ordinary history separate', async () => {
    const { userId, trackId } = await fixtures();
    const controller = new HomeController(service);

    expect(() => controller.recordPlay()).toThrow(GoneException);

    await Promise.all([
      service.recordRecent(userId, trackId),
      service.recordRecent(userId, trackId),
    ]);

    expect(await prisma.recentlyPlayed.count({ where: { userId, trackId } })).toBe(1);
    expect(await prisma.listeningEvent.count({ where: { userId, trackId } })).toBe(0);
  });
});
