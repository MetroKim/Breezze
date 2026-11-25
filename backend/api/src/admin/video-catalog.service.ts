import { Injectable, NotAcceptableException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { MediaSigner } from '../playback/media-signer.service';
import { inspectSignedVideoObject } from '../playback/signed-media-presence';

/**
 * Admin-only ingest control plane. A YouTube metadata ID, catalog match or
 * permission row alone never authorizes third-party content redistribution.
 */
@Injectable()
export class VideoCatalogAdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly signer: MediaSigner,
  ) {}

  private async requireInternalVideoRights(trackId: string) {
    const [track, permission, takedown] = await Promise.all([
      this.prisma.track.findUnique({
        where: { id: trackId }, select: { source: true, externalId: true },
      }),
      this.prisma.rightsUsagePermission.findUnique({
        where: { trackId_action: { trackId, action: 'video.play' } },
      }),
      this.prisma.contentTakedownCase.findFirst({
        where: { trackId, status: 'active' }, select: { id: true },
      }),
    ]);
    const now = new Date();
    if (!track || track.source !== 'breezze_internal' ||
        track.externalId !== null || !permission || takedown ||
        (permission.startAt && permission.startAt > now) ||
        (permission.endAt && permission.endAt <= now)) {
      throw new NotAcceptableException('VIDEO_INGEST_REQUIRES_INTERNAL_RIGHTS');
    }
  }

  async issueIngest(actorId: string, trackId: string, sizeBytes: number) {
    if (!Number.isSafeInteger(sizeBytes) || sizeBytes < 16 || sizeBytes > 95_000_000) {
      throw new NotAcceptableException('INVALID_VIDEO_INGEST_SIZE');
    }
    await this.requireInternalVideoRights(trackId);
    const existing = await this.prisma.videoAsset.findUnique({
      where: { trackId }, select: { id: true, status: true },
    });
    if (existing?.status === 'ready') {
      throw new NotAcceptableException('VIDEO_ASSET_ALREADY_READY');
    }
    const asset = existing ?? await this.prisma.videoAsset.create({
      data: { trackId, status: 'pending', mimeType: 'video/mp4' },
      select: { id: true, status: true },
    });
    const grant = this.signer.createVideoIngestUrl(asset.id, sizeBytes);
    await this.prisma.adminAuditEvent.create({
      data: {
        actorId, action: 'video.ingest_grant.issued',
        targetType: 'video_asset', targetId: asset.id,
        metadata: { trackId, mimeType: 'video/mp4', sizeBytes },
      },
    });
    return {
      ...grant, assetId: asset.id, trackId,
      mimeType: 'video/mp4', sizeBytes, method: 'PUT',
    };
  }

  async verifyAsset(actorId: string, assetId: string) {
    const asset = await this.prisma.videoAsset.findUnique({
      where: { id: assetId },
      select: { id: true, status: true, mimeType: true, trackId: true },
    });
    if (!asset || asset.mimeType !== 'video/mp4') {
      throw new NotFoundException('VIDEO_ASSET_UNAVAILABLE');
    }
    await this.requireInternalVideoRights(asset.trackId);
    // Verify a real object at a trusted HTTPS CDN origin. No URL or size is
    // accepted from the admin/client and no signature appears in audit logs.
    const signed = this.signer.createVideoUrl(asset.id, 'stream');
    const scanned = await inspectSignedVideoObject(signed.url, { force: true });
    if (!scanned || scanned.mimeType !== 'video/mp4' || scanned.sizeBytes < 16) {
      throw new NotFoundException('VIDEO_ASSET_NOT_INGESTED');
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.videoAsset.update({
        where: { id: assetId },
        data: { status: 'ready' },
      });
      await tx.adminAuditEvent.create({
        data: {
          actorId, action: 'video.asset.verified',
          targetType: 'video_asset', targetId: assetId,
          metadata: { trackId: asset.trackId, mimeType: 'video/mp4',
            sizeBytes: scanned.sizeBytes },
        },
      });
    });
    return { assetId, status: 'ready', mimeType: 'video/mp4',
      sizeBytes: scanned.sizeBytes };
  }
}
