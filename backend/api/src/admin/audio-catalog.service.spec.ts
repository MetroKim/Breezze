import { NotAcceptableException } from '@nestjs/common';
import { AudioCatalogAdminService } from './audio-catalog.service';
import { PrismaService } from '../prisma.service';
import { MediaSigner } from '../playback/media-signer.service';
import * as presence from '../playback/signed-media-presence';

describe('privileged audio catalogue provisioning', () => {
  const tx = {
    audioAssetVariant: { upsert: jest.fn() },
    catalogPlaybackMatch: { upsert: jest.fn() },
    adminAuditEvent: { create: jest.fn() },
  };
  const prisma = {
    track: { findUnique: jest.fn() },
    audioAssetVariant: { count: jest.fn() },
    rightsUsagePermission: { findUnique: jest.fn() },
    contentTakedownCase: { findFirst: jest.fn() },
    $transaction: jest.fn(async (fn: (tx: typeof tx) => Promise<unknown>) => fn(tx)),
  };
  const signer = { createPlaybackUrl: jest.fn().mockReturnValue({
    url: 'https://media.breezze.example/audio/recording/AAC_256?e=1&s=signature',
    expiresAt: new Date(Date.now() + 600000),
  }) };
  const service = new AudioCatalogAdminService(
    prisma as unknown as PrismaService, signer as unknown as MediaSigner,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({
      source: 'breezze_internal', externalId: null,
    });
    prisma.audioAssetVariant.count.mockResolvedValue(1);
    prisma.rightsUsagePermission.findUnique.mockResolvedValue({
      startAt: null, endAt: null,
    });
    prisma.contentTakedownCase.findFirst.mockResolvedValue(null);
  });

  it('never verifies external metadata as internal audio', async () => {
    prisma.track.findUnique.mockResolvedValue({
      source: 'youtube_music', externalId: 'bz:youtube_music:abcdefghijk',
    });
    await expect(service.verifyAsset('admin', 'recording', 'AAC_256'))
      .rejects.toBeInstanceOf(NotAcceptableException);
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it('refuses catalog mapping without a verified asset and explicit full rights', async () => {
    prisma.audioAssetVariant.count.mockResolvedValue(0);
    await expect(service.approveMatch('admin', 'bz:youtube_music:abcdefghijk', 'recording'))
      .rejects.toThrow('MATCH_RECORDING_NOT_PLAYABLE');
    expect(tx.catalogPlaybackMatch.upsert).not.toHaveBeenCalled();
  });

  it('approves only an audited, explicitly verified recording mapping', async () => {
    await expect(service.approveMatch('admin', 'bz:youtube_music:abcdefghijk', 'recording'))
      .resolves.toMatchObject({ status: 'approved', playableTrackId: 'recording' });
    expect(tx.catalogPlaybackMatch.upsert).toHaveBeenCalledWith(expect.objectContaining({
      create: expect.objectContaining({ status: 'approved', playableTrackId: 'recording' }),
    }));
    expect(tx.adminAuditEvent.create).toHaveBeenCalled();
  });

  it('validates audio asset quality before trusting a signed URL', async () => {
    await expect(service.verifyAsset('admin', 'recording', '../../invalid'))
      .rejects.toThrow('INVALID_AUDIO_QUALITY');
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it('accepts a verified CDN HEAD for an internal audio asset', async () => {
    const scan = jest.spyOn(presence, 'inspectSignedMediaObject')
      .mockResolvedValue({ mimeType: 'audio/mp4', sizeBytes: 2048 });
    try {
      await expect(service.verifyAsset('admin', 'recording', 'AAC_256'))
        .resolves.toMatchObject({ status: 'ready', sizeBytes: 2048 });
      expect(tx.audioAssetVariant.upsert).toHaveBeenCalledWith(expect.objectContaining({
        create: expect.objectContaining({ status: 'ready', sizeBytes: 2048n }),
      }));
      expect(scan).toHaveBeenCalledWith(expect.any(String), { force: true });
    } finally {
      scan.mockRestore();
    }
  });
});
