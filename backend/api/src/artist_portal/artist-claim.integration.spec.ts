import { randomUUID } from 'node:crypto';
import { Prisma, PrismaClient } from '@prisma/client';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

describeIntegration('Artist claim PostgreSQL concurrency constraints', () => {
  const createdUserIds: string[] = [];
  const createdArtistIds: string[] = [];

  beforeAll(async () => {
    await prisma.$connect();
  });

  afterAll(async () => {
    if (createdUserIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: createdUserIds } } });
    }
    if (createdArtistIds.length) {
      await prisma.artist.deleteMany({ where: { id: { in: createdArtistIds } } });
    }
    await prisma.$disconnect();
  });

  async function createUser() {
    const user = await prisma.user.create({
      data: {
        email: `artist-claim-${randomUUID()}@integration.invalid`,
        passwordHash: 'integration-only-not-a-real-password',
      },
      select: { id: true },
    });
    createdUserIds.push(user.id);
    return user.id;
  }

  async function createArtist() {
    const artist = await prisma.artist.create({
      data: { name: `Integration Artist ${randomUUID()}` },
      select: { id: true },
    });
    createdArtistIds.push(artist.id);
    return artist.id;
  }

  it('allows only one concurrent claim for the same account and artist', async () => {
    const userId = await createUser();
    const artistId = await createArtist();

    const attempts = await Promise.allSettled([
      prisma.artistClaim.create({ data: { userId, artistId, status: 'pending' } }),
      prisma.artistClaim.create({ data: { userId, artistId, status: 'pending' } }),
    ]);

    expect(attempts.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    const rejected = attempts.find((result) => result.status === 'rejected');
    expect(rejected?.status).toBe('rejected');
    if (rejected?.status === 'rejected') {
      expect(rejected.reason).toBeInstanceOf(Prisma.PrismaClientKnownRequestError);
      expect(rejected.reason.code).toBe('P2002');
    }
    await expect(prisma.artistClaim.count({ where: { userId, artistId } })).resolves.toBe(1);
  });

  it('allows only one account to hold an approved claim for an artist', async () => {
    const userA = await createUser();
    const userB = await createUser();
    const artistId = await createArtist();

    const attempts = await Promise.allSettled([
      prisma.artistClaim.create({ data: { userId: userA, artistId, status: 'approved' } }),
      prisma.artistClaim.create({ data: { userId: userB, artistId, status: 'approved' } }),
    ]);

    expect(attempts.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    const rejected = attempts.find((result) => result.status === 'rejected');
    expect(rejected?.status).toBe('rejected');
    if (rejected?.status === 'rejected') {
      expect(rejected.reason).toBeInstanceOf(Prisma.PrismaClientKnownRequestError);
      expect(rejected.reason.code).toBe('P2002');
    }
    await expect(prisma.artistClaim.count({ where: { artistId, status: 'approved' } })).resolves.toBe(1);
  });
});
