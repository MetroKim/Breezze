import { NotAcceptableException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { MediaSigner } from '../playback/media-signer.service';
import { inspectSignedVideoObject } from '../playback/signed-media-presence';
import { VideoCatalogAdminService } from './video-catalog.service';

jest.mock('../playback/signed-media-presence', () => ({
  inspectSignedVideoObject: jest.fn(),
}));

describe('privileged licensed MP4 ingest and readiness', () => {
  const assetId = '123e4567-e89b-42d3-a456-426614174000';
  const trackId = '123e4567-e89b-42d3-a456-426614174001';
  const prisma = {
    track: { findUnique: jest.fn() },
    rightsUsagePermission: { findUnique: jest.fn() },
    contentTakedownCase: { findFirst: jest.fn() },
    videoAsset: { findUnique: jest.fn(), create: jest.fn(), update: jest.fn() },
    adminAuditEvent: { create: jest.fn() },
    $transaction: jest.fn(),
  };
  const signer = {
    createVideoIngestUrl: jest.fn(),
    createVideoUrl: jest.fn(),
  };
  let service: VideoCatalogAdminService;
  const inspect = inspectSignedVideoObject as jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findUnique.mockResolvedValue({
      source: 'breezze_internal', externalId: null,
    });
    prisma.rightsUsagePermission.findUnique.mockResolvedValue({
      action: 'video.play', startAt: null, endAt: null,
    });
    prisma.contentTakedownCase.findFirst.mockResolvedValue(null);
    prisma.videoAsset.findUnique.mockResolvedValue(null);
    prisma.videoAsset.create.mockResolvedValue({
      id: assetId, status: 'pending',
    });
    signer.createVideoIngestUrl.mockReturnValue({
      url: 'https://media.breezze.example/ingest/video/' + assetId + '?b=512&e=1&s=redacted',
      expiresAt: new Date(Date.now() + 600_000),
    });
    signer.createVideoUrl.mockReturnValue({
      url: 'https://media.breezze.example/video/' + assetId + '/stream?e=9999999999999&s=redacted',
      expiresAt: new Date(Date.now() + 600_000),
    });
    inspect.mockResolvedValue({ mimeType: 'video/mp4', sizeBytes: 512 });
    prisma.$transaction.mockImplementation(async (action) => action(prisma));
    service = new VideoCatalogAdminService(
      prisma as unknown as PrismaService,
      signer as unknown as MediaSigner,
    );
  });

  it('issues exactly one admin-only signed ingest grant for an internal rights-cleared track', async () => {
    const issued = await service.issueIngest('admin', trackId, 512);
    expect(issued).toMatchObject({
      method: 'PUT', assetId, trackId, mimeType: 'video/mp4', sizeBytes: 512,
    });
    expect(prisma.videoAsset.create).toHaveBeenCalledWith({
      data: { trackId, status: 'pending', mimeType: 'video/mp4' },
      select: { id: true, status: true },
    });
    expect(prisma.adminAuditEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        action: 'video.ingest_grant.issued', actorId: 'admin',
      }),
    });
  });

  it('never grants ingest from third-party YouTube metadata, expired rights or takedowns', async () => {
    prisma.track.findUnique.mockResolvedValueOnce({
      source: 'youtube_music', externalId: 'bz:youtube_music:aqz-KE-bpKQ',
    });
    await expect(service.issueIngest('admin', trackId, 512))
      .rejects.toBeInstanceOf(NotAcceptableException);
    prisma.contentTakedownCase.findFirst.mockResolvedValueOnce({ id: 'case' });
    await expect(service.issueIngest('admin', trackId, 512))
      .rejects.toBeInstanceOf(NotAcceptableException);
    prisma.rightsUsagePermission.findUnique.mockResolvedValueOnce({
      startAt: null, endAt: new Date(Date.now() - 1000),
    });
    await expect(service.issueIngest('admin', trackId, 512))
      .rejects.toBeInstanceOf(NotAcceptableException);
    expect(prisma.videoAsset.create).not.toHaveBeenCalled();
    expect(signer.createVideoIngestUrl).not.toHaveBeenCalled();
  });

  it('refuses already ready objects and excessive uploads before signing', async () => {
    prisma.videoAsset.findUnique.mockResolvedValue({ id: assetId, status: 'ready' });
    await expect(service.issueIngest('admin', trackId, 512))
      .rejects.toThrow('VIDEO_ASSET_ALREADY_READY');
    await expect(service.issueIngest('admin', trackId, 95_000_001))
      .rejects.toThrow('INVALID_VIDEO_INGEST_SIZE');
    expect(signer.createVideoIngestUrl).not.toHaveBeenCalled();
  });

  it('promotes only a real R2 MP4 object after signed HEAD verification', async () => {
    prisma.videoAsset.findUnique.mockResolvedValue({
      id: assetId, trackId, status: 'pending', mimeType: 'video/mp4',
    });
    await expect(service.verifyAsset('admin', assetId)).resolves.toEqual({
      assetId, status: 'ready', mimeType: 'video/mp4', sizeBytes: 512,
    });
    expect(inspect).toHaveBeenCalledWith(
      expect.stringContaining('/video/' + assetId + '/stream'),
      { force: true },
    );
    expect(prisma.videoAsset.update).toHaveBeenCalledWith({
      where: { id: assetId }, data: { status: 'ready' },
    });
    expect(prisma.adminAuditEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ action: 'video.asset.verified' }),
    });
  });

  it('does not promote a missing R2 asset or an untrusted MIME type', async () => {
    prisma.videoAsset.findUnique.mockResolvedValue({
      id: assetId, trackId, status: 'pending', mimeType: 'video/mp4',
    });
    inspect.mockResolvedValueOnce({ mimeType: 'text/html', sizeBytes: 512 });
    await expect(service.verifyAsset('admin', assetId))
      .rejects.toBeInstanceOf(NotFoundException);
    inspect.mockResolvedValueOnce(null);
    await expect(service.verifyAsset('admin', assetId))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.videoAsset.update).not.toHaveBeenCalled();
  });
});
