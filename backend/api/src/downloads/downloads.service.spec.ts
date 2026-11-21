import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from '../playback/media-signer.service';
import { DownloadsService } from './downloads.service';

describe('DownloadsService', () => {
  const prisma = { downloadRecord: { upsert: jest.fn(), findFirst: jest.fn(), updateMany: jest.fn() } };
  const rights = { decide: jest.fn() };
  const signer = { createPlaybackUrl: jest.fn() };
  let service: DownloadsService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new DownloadsService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
      signer as unknown as MediaSigner,
    );
  });

  it('revokes an existing offline lease when rights are no longer valid', async () => {
    prisma.downloadRecord.findFirst.mockResolvedValue({ id: 'download-1' });
    rights.decide.mockResolvedValue({
      allowed: false, previewOnly: false, reason: 'TAKEDOWN_ACTIVE',
    });
    await expect(service.revalidateOfflineLease('user-1', 'track-1', 'TZ'))
      .resolves.toEqual({ allowed: false, reason: 'TAKEDOWN_ACTIVE' });
    expect(prisma.downloadRecord.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', trackId: 'track-1', status: 'active' },
      data: expect.objectContaining({ status: 'revoked', expiresAt: expect.any(Date) }),
    });
  });

  it('extends a valid offline lease by at most 72 hours', async () => {
    prisma.downloadRecord.findFirst.mockResolvedValue({ id: 'download-1' });
    prisma.downloadRecord.updateMany.mockResolvedValue({ count: 1 });
    rights.decide.mockResolvedValue({
      allowed: true, previewOnly: false, reason: 'OK', expiresAt: null,
    });
    const before = Date.now();
    const result = await service.revalidateOfflineLease('user-1', 'track-1', 'TZ');
    expect(result.allowed).toBe(true);
    if (!result.allowed) throw new Error('LEASE_REVALIDATION_DENIED');
    expect(result.offlineLeaseExpiresAt.getTime()).toBeGreaterThanOrEqual(before + 72 * 60 * 60 * 1000 - 1000);
    expect(result.offlineLeaseExpiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 72 * 60 * 60 * 1000);
  });

  it('does not create a download for a preview-only decision', async () => {
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: true,
      reason: 'OK',
      qualityRestriction: null,
      expiresAt: null,
      attribution: null,
    });

    await expect(
      service.authorizeAndRecord('user-1', {
        trackId: 'track-1',
        territory: 'TZ',
      }),
    ).resolves.toEqual({
      allowed: false,
      reason: 'PREVIEW_ONLY',
      url: null,
    });

    expect(prisma.downloadRecord.upsert).not.toHaveBeenCalled();
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it('bounds offline authorization to 72 hours when rights have no end date', async () => {
    rights.decide.mockResolvedValue({
      allowed: true, previewOnly: false, reason: 'OK',
      qualityRestriction: null, expiresAt: null, attribution: null,
    });
    prisma.downloadRecord.upsert.mockResolvedValue({ id: 'download-lease' });
    signer.createPlaybackUrl.mockReturnValue({
      url: 'https://cdn.example/download', expiresAt: new Date(Date.now() + 60_000),
    });
    const before = Date.now();
    const result = await service.authorizeAndRecord('user-1', {
      trackId: 'track-1', territory: 'TZ',
    });
    const saved = prisma.downloadRecord.upsert.mock.calls[0][0];
    expect(saved.create.expiresAt.getTime()).toBeGreaterThanOrEqual(before + 72 * 60 * 60 * 1000 - 1000);
    expect(saved.create.expiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 72 * 60 * 60 * 1000);
    expect(result.offlineLeaseExpiresAt).toEqual(saved.create.expiresAt);
  });

  it('records and signs a download only after explicit authorization', async () => {
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
      reason: 'OK',
      qualityRestriction: null,
      expiresAt: null,
      attribution: 'Licensed via label',
    });
    prisma.downloadRecord.upsert.mockResolvedValue({ id: 'download-1' });
    signer.createPlaybackUrl.mockReturnValue({
      url: 'https://cdn.example/download',
      expiresAt: new Date(Date.now() + 60_000),
    });

    await expect(
      service.authorizeAndRecord('user-1', {
        trackId: 'track-1',
        territory: 'TZ',
      }),
    ).resolves.toMatchObject({
      allowed: true,
      url: 'https://cdn.example/download',
      recordId: 'download-1',
    });

    expect(signer.createPlaybackUrl).toHaveBeenCalledWith('track-1', 'download', null);
  });
});
