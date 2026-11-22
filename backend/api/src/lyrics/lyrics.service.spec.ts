import { NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { LyricsService } from './lyrics.service';

describe('LyricsService', () => {
  const prisma = {
    lyrics: { findUnique: jest.fn() },
    lyricTranslation: { findMany: jest.fn() },
  };
  const rights = { decide: jest.fn() };
  let service: LyricsService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new LyricsService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
    );
  });

  it('returns translations only after a track-specific territory rights check', async () => {
    prisma.lyrics.findUnique.mockResolvedValue({
      id: 'lyrics-1',
      trackId: 'track-1',
    });
    rights.decide.mockResolvedValue({
      allowed: true,
      reason: 'OK',
      previewOnly: false,
      qualityRestriction: null,
      expiresAt: null,
      attribution: null,
    });
    prisma.lyricTranslation.findMany.mockResolvedValue([
      { lyricsId: 'lyrics-1', language: 'sw', text: '...' },
    ]);

    await expect(
      service.getTranslations('user-1', 'lyrics-1', 'TZ', 'sw'),
    ).resolves.toHaveLength(1);

    expect(rights.decide).toHaveBeenCalledWith({
      userId: 'user-1',
      trackId: 'track-1',
      action: 'lyrics.translate',
      territory: 'TZ',
    });
    expect(prisma.lyricTranslation.findMany).toHaveBeenCalledWith({
      where: { lyricsId: 'lyrics-1', language: 'sw' },
      orderBy: { language: 'asc' },
    });
  });

  it('does not disclose translations when translation rights are denied', async () => {
    prisma.lyrics.findUnique.mockResolvedValue({
      id: 'lyrics-1',
      trackId: 'track-1',
    });
    rights.decide.mockResolvedValue({
      allowed: false,
      reason: 'NO_EXPLICIT_AUTHORIZATION',
    });

    await expect(
      service.getTranslations('user-1', 'lyrics-1', 'TZ'),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.lyricTranslation.findMany).not.toHaveBeenCalled();
  });

  it('does not disclose whether translations exist for an unknown lyrics record', async () => {
    prisma.lyrics.findUnique.mockResolvedValue(null);

    await expect(
      service.getTranslations('user-1', 'missing', 'TZ'),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(rights.decide).not.toHaveBeenCalled();
    expect(prisma.lyricTranslation.findMany).not.toHaveBeenCalled();
  });
});
