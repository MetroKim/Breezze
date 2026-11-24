import { Injectable, NotAcceptableException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from '../playback/media-signer.service';

/**
 * Signed R2 MP4 delivery for explicitly imported Breezze-owned video assets.
 * YouTube search/ytmusicapi metadata can never become a VideoAsset grant.
 */
@Injectable()
export class VideoAssetsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
    private readonly signer: MediaSigner,
  ) {}

  private requireTerritory(edgeCountry?: string): string {
    const territory = edgeCountry?.trim().toUpperCase();
    if (!territory || !/^[A-Z]{2}$/.test(territory)) {
      throw new NotAcceptableException('VIDEO_TERRITORY_UNAVAILABLE');
    }
    return territory;
  }

  private async asset(assetId: string) {
    const asset = await this.prisma.videoAsset.findUnique({
      where: { id: assetId },
      select: {
        id: true,
        status: true,
        mimeType: true,
        track: { select: { id: true, source: true } },
      },
    });
    if (!asset || asset.status !== 'ready' || asset.mimeType !== 'video/mp4' ||
        asset.track.source !== 'breezze_internal') {
      throw new NotFoundException('VIDEO_ASSET_UNAVAILABLE');
    }
    return asset;
  }

  async catalog(userId: string, edgeCountry?: string) {
    const territory = this.requireTerritory(edgeCountry);
    const assets = await this.prisma.videoAsset.findMany({
      where: {
        status: 'ready',
        mimeType: 'video/mp4',
        track: {
          source: 'breezze_internal',
          territories: { some: { territory } },
        },
      },
      take: 25,
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        track: { select: {
          id: true, title: true,
          artist: { select: { name: true } },
        } },
      },
    });
    // Catalog discovery is not a playback grant. Keep only songs whose
    // video.play rights are valid in the trusted edge territory.
    const checked = await Promise.all(assets.map(async (asset) => {
      const playback = await this.rights.decide({
        userId, trackId: asset.track.id, territory, action: 'video.play',
      });
      if (!playback.allowed || playback.previewOnly) return null;
      const download = await this.rights.decide({
        userId, trackId: asset.track.id, territory, action: 'video.download',
      });
      return {
        id: asset.id,
        videoAssetId: asset.id,
        trackId: asset.track.id,
        title: asset.track.title,
        artist: asset.track.artist.name,
        downloadAvailable: download.allowed && !download.previewOnly,
      };
    }));
    return {
      source: 'Breezze licensed videos',
      territory,
      fetchedAt: new Date().toISOString(),
      items: checked.filter((item) => item !== null),
    };
  }

  async playback(userId: string, assetId: string, edgeCountry?: string) {
    const territory = this.requireTerritory(edgeCountry);
    const asset = await this.asset(assetId);
    const decision = await this.rights.decide({
      userId, trackId: asset.track.id, territory, action: 'video.play',
    });
    if (!decision.allowed || decision.previewOnly) {
      throw new NotAcceptableException(decision.previewOnly ? 'PREVIEW_ONLY' : decision.reason);
    }
    const signed = this.signer.createVideoUrl(asset.id, 'stream', decision.expiresAt);
    return {
      videoAssetId: asset.id,
      streamUrl: signed.url,
      expiresAt: signed.expiresAt,
      mimeType: 'video/mp4',
      attribution: decision.attribution,
    };
  }

  async authorizeDownload(userId: string, assetId: string, edgeCountry?: string) {
    const territory = this.requireTerritory(edgeCountry);
    const asset = await this.asset(assetId);
    const decision = await this.rights.decide({
      userId, trackId: asset.track.id, territory, action: 'video.download',
    });
    if (!decision.allowed || decision.previewOnly) {
      return {
        allowed: false, reason: decision.previewOnly ? 'PREVIEW_ONLY' : decision.reason,
        url: null,
      };
    }
    const offlineLeaseExpiresAt = new Date(Math.min(
      Date.now() + 72 * 60 * 60 * 1000,
      decision.expiresAt?.getTime() ?? Number.POSITIVE_INFINITY,
    ));
    if (offlineLeaseExpiresAt.getTime() <= Date.now()) {
      return { allowed: false, reason: 'RIGHTS_EXPIRED', url: null };
    }
    const signed = this.signer.createVideoUrl(asset.id, 'download', decision.expiresAt);
    const record = await this.prisma.videoDownloadRecord.upsert({
      where: { userId_videoAssetId: { userId, videoAssetId: asset.id } },
      create: {
        userId, videoAssetId: asset.id, expiresAt: offlineLeaseExpiresAt,
      },
      update: { status: 'active', expiresAt: offlineLeaseExpiresAt },
    });
    return {
      allowed: true,
      reason: 'OK',
      url: signed.url,
      recordId: record.id,
      videoAssetId: asset.id,
      mimeType: 'video/mp4',
      expiresAt: signed.expiresAt,
      offlineLeaseExpiresAt,
      attribution: decision.attribution,
    };
  }

  async revalidate(userId: string, assetId: string, edgeCountry?: string) {
    const territory = this.requireTerritory(edgeCountry);
    const existing = await this.prisma.videoDownloadRecord.findUnique({
      where: { userId_videoAssetId: { userId, videoAssetId: assetId } },
      select: { status: true },
    });
    if (!existing || existing.status !== 'active') {
      return { allowed: false, reason: 'VIDEO_DOWNLOAD_NOT_FOUND' };
    }
    const revoke = async (reason: string) => {
      await this.prisma.videoDownloadRecord.updateMany({
        where: { userId, videoAssetId: assetId, status: 'active' },
        data: { status: 'revoked', expiresAt: new Date() },
      });
      return { allowed: false, reason };
    };
    let asset;
    try {
      asset = await this.asset(assetId);
    } catch (error) {
      if (!(error instanceof NotFoundException)) throw error;
      return revoke('VIDEO_ASSET_UNAVAILABLE');
    }
    const decision = await this.rights.decide({
      userId, trackId: asset.track.id, territory, action: 'video.download',
    });
    if (!decision.allowed || decision.previewOnly) {
      return revoke(decision.previewOnly ? 'PREVIEW_ONLY' : decision.reason);
    }
    const offlineLeaseExpiresAt = new Date(Math.min(
      Date.now() + 72 * 60 * 60 * 1000,
      decision.expiresAt?.getTime() ?? Number.POSITIVE_INFINITY,
    ));
    if (offlineLeaseExpiresAt.getTime() <= Date.now()) return revoke('RIGHTS_EXPIRED');
    await this.prisma.videoDownloadRecord.updateMany({
      where: { userId, videoAssetId: assetId, status: 'active' },
      data: { expiresAt: offlineLeaseExpiresAt },
    });
    return { allowed: true, offlineLeaseExpiresAt };
  }

  async list(userId: string) {
    const items = await this.prisma.videoDownloadRecord.findMany({
      where: { userId, status: 'active' },
      orderBy: { createdAt: 'desc' },
      select: {
        videoAssetId: true,
        status: true,
        expiresAt: true,
        createdAt: true,
        videoAsset: { select: { track: { select: { id: true, title: true } } } },
      },
    });
    return { items };
  }

  async remove(userId: string, assetId: string) {
    const result = await this.prisma.videoDownloadRecord.deleteMany({
      where: { userId, videoAssetId: assetId },
    });
    if (!result.count) throw new NotFoundException('VIDEO_DOWNLOAD_NOT_FOUND');
    return { removed: true };
  }
}
