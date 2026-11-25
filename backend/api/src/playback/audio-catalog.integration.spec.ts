import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';

const databaseUrl = process.env.INTEGRATION_DATABASE_URL;
const describeIntegration = databaseUrl ? describe : describe.skip;
const prisma = new PrismaClient(
  databaseUrl ? { datasources: { db: { url: databaseUrl } } } : undefined,
);

/**
 * Real PostgreSQL migration acceptance, not mocked Prisma models.
 * No media bytes, credentials, or provider bearer URLs enter the database.
 */
describeIntegration('Audio catalog PostgreSQL migration constraints', () => {
  const ownedTracks: string[] = [];
  const ownedArtists: string[] = [];
  const sourceIds: string[] = [];

  beforeAll(async () => { await prisma.$connect(); });

  afterAll(async () => {
    if (sourceIds.length) {
      await prisma.catalogPlaybackMatch.deleteMany({
        where: { externalTrackId: { in: sourceIds } },
      });
    }
    if (ownedTracks.length) {
      await prisma.track.deleteMany({ where: { id: { in: ownedTracks } } });
    }
    if (ownedArtists.length) {
      await prisma.artist.deleteMany({ where: { id: { in: ownedArtists } } });
    }
    await prisma.$disconnect();
  });

  async function createInternalRecording() {
    const artist = await prisma.artist.create({
      data: { name: `CI Audio Artist ${randomUUID()}` }, select: { id: true },
    });
    ownedArtists.push(artist.id);
    const track = await prisma.track.create({
      data: {
        title: 'CI full-length recording', artistId: artist.id,
        duration: 240, source: 'breezze_internal',
      }, select: { id: true },
    });
    ownedTracks.push(track.id);
    return track.id;
  }

  it('persists verified formats and an approved catalog link to that internal recording', async () => {
    const trackId = await createInternalRecording();
    const externalTrackId = `bz:youtube_music:${randomUUID().replace(/-/g, '').slice(0, 11)}`;
    sourceIds.push(externalTrackId);

    const variant = await prisma.audioAssetVariant.create({
      data: {
        trackId, quality: 'AAC_256', status: 'ready',
        mimeType: 'audio/mp4', sizeBytes: 32768n, verifiedAt: new Date(),
      },
    });
    expect(variant.sizeBytes).toBe(32768n);

    await prisma.catalogPlaybackMatch.create({
      data: {
        source: 'youtube_music', externalTrackId, playableTrackId: trackId,
        status: 'approved', verifiedAt: new Date(),
      },
    });
    const match = await prisma.catalogPlaybackMatch.findUnique({
      where: {
        source_externalTrackId: { source: 'youtube_music', externalTrackId },
      },
      include: { playableTrack: true },
    });
    expect(match?.status).toBe('approved');
    expect(match?.playableTrack.id).toBe(trackId);
    expect(match?.playableTrack.source).toBe('breezze_internal');
  });

  it('rejects falsely ready and falsely approved metadata in real PostgreSQL', async () => {
    const trackId = await createInternalRecording();
    await expect(prisma.audioAssetVariant.create({
      data: {
        trackId, quality: 'AAC_128', mimeType: 'audio/mp4',
        status: 'ready', sizeBytes: 10000n,
        // No verifiedAt: storage bytes were not actually verified.
      },
    })).rejects.toThrow();

    const externalTrackId = `bz:youtube_music:${randomUUID().replace(/-/g, '').slice(0, 11)}`;
    sourceIds.push(externalTrackId);
    await expect(prisma.catalogPlaybackMatch.create({
      data: {
        source: 'youtube_music', externalTrackId,
        playableTrackId: trackId, status: 'approved',
        // No verifiedAt: mere catalog similarity is not an approved match.
      },
    })).rejects.toThrow();

    expect(await prisma.catalogPlaybackMatch.count({
      where: { source: 'youtube_music', externalTrackId },
    })).toBe(0);
  });
});
