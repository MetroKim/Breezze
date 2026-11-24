import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from '../playback/media-signer.service';
import { VideoAssetsService } from './video-assets.service';

describe('VideoAssetsService', () => {
  const assetId = '123e4567-e89b-42d3-a456-426614174000';
  const prisma = {
    videoAsset: { findUnique: jest.fn() },
    videoDownloadRecord: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
      updateMany: jest.fn(),
      findMany: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
  const rights = { decide: jest.fn() };
  const signer = { createVideoUrl: jest.fn() };
  let service: VideoAssetsService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.videoAsset.findUnique.mockResolvedValue({
      id: assetId,
      status: 'ready',
      mimeType: 'video/mp4',
      track: { id: 'track-1', source: 'breezze_internal' },
    });
    rights.decide.mockResolvedValue({
      allowed: true, previewOnly: false, reason: 'OK',
      expiresAt: null, attribution: null,
    });
    signer.createVideoUrl.mockReturnValue({
      url: 'https://cdn.breezze.test/video/' + assetId + '/download?e=1&s=ok',
      expiresAt: new Date(Date.now() + 60_000),
    });
    prisma.videoDownloadRecord.upsert.mockResolvedValue({ id: 'download-1' });
    prisma.videoDownloadRecord.findUnique.mockResolvedValue({ status: 'active' });
    prisma.videoDownloadRecord.updateMany.mockResolvedValue({ count: 1 });
    prisma.videoDownloadRecord.deleteMany.mockResolvedValue({ count: 1 });
    service = new VideoAssetsService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
      signer as unknown as MediaSigner,
    );
  });

  it('requires a trusted two-letter edge country before reading an asset', async () => {
    await expect(service.playback('user-1', assetId, undefined))
      .rejects.toThrow('VIDEO_TERRITORY_UNAVAILABLE');
    await expect(service.authorizeDownload('user-1', assetId, 'not-a-country'))
      .rejects.toThrow('VIDEO_TERRITORY_UNAVAILABLE');
    expect(prisma.videoAsset.findUnique).not.toHaveBeenCalled();
    expect(rights.decide).not.toHaveBeenCalled();
  });

  it('fails closed for metadata-only YouTube and unready/untrusted video objects', async () => {
    for (const source of ['youtube_music', 'deezer', null]) {
      prisma.videoAsset.findUnique.mockResolvedValueOnce({
        id: assetId, status: 'ready', mimeType: 'video/mp4',
        track: { id: 'track-1', source },
      });
      await expect(service.playback('user-1', assetId, 'TZ'))
        .rejects.toThrow('VIDEO_ASSET_UNAVAILABLE');
    }
    prisma.videoAsset.findUnique.mockResolvedValueOnce({
      id: assetId, status: 'pending', mimeType: 'video/mp4',
      track: { id: 'track-1', source: 'breezze_internal' },
    });
    await expect(service.authorizeDownload('user-1', assetId, 'TZ'))
      .rejects.toThrow('VIDEO_ASSET_UNAVAILABLE');
    expect(rights.decide).not.toHaveBeenCalled();
    expect(signer.createVideoUrl).not.toHaveBeenCalled();
  });

  it('needs distinct video.play and video.download rights', async () => {
    await service.playback('user-1', assetId, 'TZ');
    await service.authorizeDownload('user-1', assetId, 'TZ');
    expect(rights.decide).toHaveBeenNthCalledWith(1, {
      userId: 'user-1', trackId: 'track-1', territory: 'TZ',
      action: 'video.play',
    });
    expect(rights.decide).toHaveBeenNthCalledWith(2, {
      userId: 'user-1', trackId: 'track-1', territory: 'TZ',
      action: 'video.download',
    });
    expect(signer.createVideoUrl).toHaveBeenNthCalledWith(1, assetId, 'stream', null);
    expect(signer.createVideoUrl).toHaveBeenNthCalledWith(2, assetId, 'download', null);
  });

  it('denies preview-only video rights without recording an offline lease', async () => {
    rights.decide.mockResolvedValue({ allowed: true, previewOnly: true, reason: 'OK' });
    await expect(service.playback('user-1', assetId, 'TZ'))
      .rejects.toThrow('PREVIEW_ONLY');
    await expect(service.authorizeDownload('user-1', assetId, 'TZ'))
      .resolves.toEqual({ allowed: false, reason: 'PREVIEW_ONLY', url: null });
    expect(prisma.videoDownloadRecord.upsert).not.toHaveBeenCalled();
    expect(signer.createVideoUrl).not.toHaveBeenCalled();
  });

  it('saves a user-scoped 72-hour offline lease, capped by rights expiry', async () => {
    const expiry = new Date(Date.now() + 3_600_000);
    rights.decide.mockResolvedValue({
      allowed: true, previewOnly: false, expiresAt: expiry, reason: 'OK',
    });
    const result = await service.authorizeDownload('user-1', assetId, 'TZ');
    expect(result).toMatchObject({
      allowed: true, videoAssetId: assetId,
      offlineLeaseExpiresAt: expiry,
    });
    expect(prisma.videoDownloadRecord.upsert).toHaveBeenCalledWith({
      where: {
        userId_videoAssetId: { userId: 'user-1', videoAssetId: assetId },
      },
      create: {
        userId: 'user-1', videoAssetId: assetId, expiresAt: expiry,
      },
      update: { status: 'active', expiresAt: expiry },
    });
    expect(signer.createVideoUrl).toHaveBeenCalledWith(assetId, 'download', expiry);
  });

  it('revokes an active video lease on takedown or withdrawn rights', async () => {
    rights.decide.mockResolvedValue({ allowed: false, previewOnly: false, reason: 'TAKEDOWN_ACTIVE' });
    await expect(service.revalidate('user-1', assetId, 'TZ'))
      .resolves.toEqual({ allowed: false, reason: 'TAKEDOWN_ACTIVE' });
    expect(prisma.videoDownloadRecord.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', videoAssetId: assetId, status: 'active' },
      data: { status: 'revoked', expiresAt: expect.any(Date) },
    });
  });

  it('does not create or revalidate a lease without an owned active record', async () => {
    prisma.videoDownloadRecord.findUnique.mockResolvedValue(null);
    await expect(service.revalidate('user-other', assetId, 'TZ'))
      .resolves.toEqual({ allowed: false, reason: 'VIDEO_DOWNLOAD_NOT_FOUND' });
    expect(rights.decide).not.toHaveBeenCalled();
    expect(prisma.videoDownloadRecord.updateMany).not.toHaveBeenCalled();
  });

  it('lists only the signed-in owner records and removes only their row', async () => {
    prisma.videoDownloadRecord.findMany.mockResolvedValue([]);
    await service.list('owner-a');
    await service.remove('owner-a', assetId);
    expect(prisma.videoDownloadRecord.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: 'owner-a', status: 'active' } }),
    );
    expect(prisma.videoDownloadRecord.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'owner-a', videoAssetId: assetId },
    });
  });
});
