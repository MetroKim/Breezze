import {
  Injectable,
  NotAcceptableException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from '../playback/media-signer.service';
import { verifySignedMediaObject } from '../playback/signed-media-presence';
import { ProviderRegistry } from '../providers/provider-registry.service';
import { isOnlineOnlyMediaMode } from '../playback/online-media-mode';

@Injectable()
export class DownloadsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
    private readonly signer: MediaSigner,
    private readonly providers: ProviderRegistry,
  ) {}

  private requireTerritory(value: string): string {
    const territory = value?.trim().toUpperCase();
    if (!territory || !/^[A-Z]{2}$/.test(territory)) {
      throw new NotAcceptableException('DOWNLOAD_TERRITORY_UNAVAILABLE');
    }
    return territory;
  }

  private async providerAllowsDownload(trackId: string): Promise<boolean> {
    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { id: true, source: true, externalId: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');

    // Only explicitly internal records (or legacy records with no external
    // identity) can use Breezze's R2 download signer. ProviderAdapter currently
    // has no authorized download-URL resolver, so external downloads remain
    // blocked even if a future adapter accidentally flips its capability flag.
    if (track.source === 'breezze_internal' || (track.source === null && track.externalId === null)) {
      return true;
    }

    const provider = track.source ? this.providers.get(track.source) : undefined;
    if (!provider || !provider.capabilities.download || !provider.capabilities.availability) {
      return false;
    }
    // A capability flag alone is not a downloadable source URL. Do not sign
    // a Breezze-owned R2 path for an asset hosted by a third-party provider.
    return false;
  }

  /** Do not mint R2 download capabilities for missing, unverified or wrong-codec media.
   * A verified SHA-256 also supplies an exact *encoded-byte* resume identity.
   * Missing hashes stay downloadable but non-resumable across sessions.
   */
  private async readyDownloadAssetVersion(trackId: string): Promise<string | null | false> {
    const asset = await this.prisma.audioAssetVariant.findUnique({
      where: { trackId_quality: { trackId, quality: 'AAC_256' } },
      select: { status: true, verifiedAt: true, sizeBytes: true, mimeType: true, sha256: true },
    });
    if (!asset || asset.status !== 'ready' || asset.verifiedAt === null ||
        asset.sizeBytes === null || asset.sizeBytes <= 0n ||
        !['audio/mp4', 'audio/aac'].includes(asset.mimeType)) {
      return false;
    }
    // SHA-256 must be an actual full-length hexadecimal digest. Other
    // metadata must never be presented as an integrity-verified version.
    const digest = asset.sha256;
    return typeof digest === 'string' && /^[0-9a-f]{64}$/i.test(digest)
      ? digest.toLowerCase()
      : null;
  }

  async authorizeAndRecord(
    userId: string,
    dto: { trackId: string; territory: string },
  ) {
    // No offline media bytes or new download records in online-only mode.
    if (isOnlineOnlyMediaMode()) {
      return { allowed: false, reason: 'ONLINE_ONLY_DOWNLOAD_DISABLED', url: null };
    }
    const territory = this.requireTerritory(dto.territory);
    const supported = await this.providerAllowsDownload(dto.trackId);
    if (!supported) {
      return {
        allowed: false,
        reason: 'PROVIDER_DOWNLOAD_UNSUPPORTED',
        url: null,
      };
    }

    const decision = await this.rights.decide({
      userId,
      trackId: dto.trackId,
      action: 'download',
      territory,
    });

    if (!decision.allowed || decision.previewOnly) {
      return {
        allowed: false,
        reason: decision.previewOnly ? 'PREVIEW_ONLY' : decision.reason,
        url: null,
      };
    }

    const assetVersion = await this.readyDownloadAssetVersion(dto.trackId);
    if (assetVersion === false) {
      return { allowed: false, reason: 'LICENSED_DOWNLOAD_VARIANT_NOT_READY', url: null };
    }

    // Offline downloads receive a bounded lease even when the underlying
    // catalogue grant has no explicit end date. Rights expiry always wins.
    const offlineLeaseExpiresAt = new Date(Math.min(
      Date.now() + 72 * 60 * 60 * 1000,
      decision.expiresAt?.getTime() ?? Number.POSITIVE_INFINITY,
    ));

    const signed = this.signer.createPlaybackUrl(
      dto.trackId,
      'download',
      decision.expiresAt,
    );
    // A ready database row alone does not prove the bytes exist at the CDN.
    // Production probes the signed private R2 object before persisting a lease.
    await verifySignedMediaObject(signed.url);
    const record = await this.prisma.downloadRecord.upsert({
      where: { userId_trackId: { userId, trackId: dto.trackId } },
      create: {
        userId,
        trackId: dto.trackId,
        expiresAt: offlineLeaseExpiresAt,
      },
      // A previously revoked record can be authorized again after rights are
      // restored. Without reactivating it, the new download is invisible to
      // list/revalidation even though this request has just been approved.
      update: { status: 'active', expiresAt: offlineLeaseExpiresAt },
    });

    return {
      allowed: true,
      reason: 'OK',
      url: signed.url,
      recordId: record.id,
      expiresAt: signed.expiresAt,
      rightsExpiresAt: decision.expiresAt,
      offlineLeaseExpiresAt,
      assetVersion,
      attribution: decision.attribution,
    };
  }

  async revalidateOfflineLease(userId: string, trackId: string, territoryInput: string) {
    if (isOnlineOnlyMediaMode()) {
      return { allowed: false, reason: 'ONLINE_ONLY_DOWNLOAD_DISABLED' };
    }
    const territory = this.requireTerritory(territoryInput);
    const existing = await this.prisma.downloadRecord.findFirst({
      where: { userId, trackId, status: 'active' },
      select: { id: true },
    });
    if (!existing) return { allowed: false, reason: 'DOWNLOAD_NOT_FOUND' };

    const supported = await this.providerAllowsDownload(trackId);
    if (!supported) {
      await this.prisma.downloadRecord.updateMany({
        where: { userId, trackId, status: 'active' },
        data: { status: 'revoked', expiresAt: new Date() },
      });
      return { allowed: false, reason: 'PROVIDER_DOWNLOAD_UNSUPPORTED' };
    }

    const decision = await this.rights.decide({
      userId, trackId, action: 'download', territory,
    });
    if (!decision.allowed || decision.previewOnly) {
      await this.prisma.downloadRecord.updateMany({
        where: { userId, trackId, status: 'active' },
        data: { status: 'revoked', expiresAt: new Date() },
      });
      return {
        allowed: false,
        reason: decision.previewOnly ? 'PREVIEW_ONLY' : decision.reason,
      };
    }

    if ((await this.readyDownloadAssetVersion(trackId)) === false) {
      await this.prisma.downloadRecord.updateMany({
        where: { userId, trackId, status: 'active' },
        data: { status: 'revoked', expiresAt: new Date() },
      });
      return { allowed: false, reason: 'LICENSED_DOWNLOAD_VARIANT_NOT_READY' };
    }

    const offlineLeaseExpiresAt = new Date(Math.min(
      Date.now() + 72 * 60 * 60 * 1000,
      decision.expiresAt?.getTime() ?? Number.POSITIVE_INFINITY,
    ));
    await this.prisma.downloadRecord.updateMany({
      where: { userId, trackId, status: 'active' },
      data: { expiresAt: offlineLeaseExpiresAt },
    });
    return { allowed: true, offlineLeaseExpiresAt };
  }

  async list(userId: string) {
    // Do not advertise legacy offline assets as usable when online-only.
    if (isOnlineOnlyMediaMode()) return [];
    return this.prisma.downloadRecord.findMany({
      where: { userId, status: 'active' },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        trackId: true,
        status: true,
        createdAt: true,
        expiresAt: true,
      },
    });
  }

  async remove(userId: string, trackId: string) {
    const result = await this.prisma.downloadRecord.deleteMany({
      where: { userId, trackId },
    });
    if (result.count === 0) {
      throw new NotFoundException('DOWNLOAD_NOT_FOUND');
    }
    return { removed: true };
  }
}
