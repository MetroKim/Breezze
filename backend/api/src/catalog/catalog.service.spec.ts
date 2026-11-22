import { NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { CatalogService } from './catalog.service';

describe('CatalogService', () => {
  const prisma = {
    artist: { upsert: jest.fn(), findUnique: jest.fn() },
    track: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
    },
    album: { findUnique: jest.fn() },
  };
  const rights = { decide: jest.fn() };
  let service: CatalogService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.artist.upsert.mockResolvedValue({ id: 'artist-1' });
    prisma.track.upsert.mockResolvedValue({ id: 'track-1' });
    rights.decide.mockResolvedValue({ allowed: true, reason: 'OK' });
    service = new CatalogService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
    );
  });

  it('atomically converges an external track ID using an upsert', async () => {
    const dto = {
      externalId: 'bz:video-1',
      source: 'youtube',
      title: 'Nightcall',
      artistName: 'Kavinsky',
      durationSec: 254,
    };

    await expect(service.resolve(dto)).resolves.toEqual({ id: 'track-1' });

    expect(prisma.artist.upsert).toHaveBeenCalledWith({
      where: { name: 'Kavinsky' },
      create: { name: 'Kavinsky' },
      update: {},
    });
    expect(prisma.track.upsert).toHaveBeenCalledWith({
      where: { externalId: 'bz:video-1' },
      create: {
        externalId: 'bz:video-1',
        source: 'youtube',
        title: 'Nightcall',
        artistId: 'artist-1',
        duration: 254,
      },
      update: {},
    });
    expect(prisma.track.findUnique).not.toHaveBeenCalled();
  });

  it('checks territory and takedown rights before returning a public track', async () => {
    prisma.track.findUnique.mockResolvedValue({
      id: 'track-1',
      title: 'Nightcall',
      artist: { id: 'artist-1' },
      album: null,
    });
    rights.decide.mockResolvedValue({ allowed: false, reason: 'TAKEDOWN_ACTIVE' });

    await expect(service.song('track-1', 'TZ'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(rights.decide).toHaveBeenCalledWith({
      userId: null,
      trackId: 'track-1',
      action: 'metadata.display',
      territory: 'TZ',
    });
  });

  it('filters unavailable and taken-down tracks from public album metadata', async () => {
    prisma.album.findUnique.mockResolvedValue({
      id: 'album-1',
      title: 'Album',
      tracks: [{ id: 'track-1' }, { id: 'track-2' }],
      artist: { id: 'artist-1' },
    });
    rights.decide.mockImplementation(({ trackId }: { trackId: string }) =>
      Promise.resolve({ allowed: trackId === 'track-1', reason: 'OK' }),
    );

    await expect(service.album('album-1', 'TZ')).resolves.toMatchObject({
      id: 'album-1',
      tracks: [{ id: 'track-1' }],
    });
  });

  it('does not expose an album when none of its tracks are visible', async () => {
    prisma.album.findUnique.mockResolvedValue({
      id: 'album-1',
      tracks: [{ id: 'track-1' }],
      artist: { id: 'artist-1' },
    });
    rights.decide.mockResolvedValue({ allowed: false, reason: 'NOT_AVAILABLE_IN_TERRITORY' });

    await expect(service.album('album-1', 'TZ'))
      .rejects.toBeInstanceOf(NotFoundException);
  });
});
