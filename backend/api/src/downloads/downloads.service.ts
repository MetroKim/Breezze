import {
  Injectable,
  NotAcceptableException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from '../playback/media-signer.service';
import { ProviderRegistry } from '../providers/provider-registry.service';

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

  private async providerAllowsDownload(
    trackId: string,
    territory: string,
  ): Promise<boolean> {
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

  async authorizeAndRecord(
    userId: string,
    dto: { trackId: string; territory: string },
  ) {
    const territory = this.requireTerritory(dto.territory);
    const supported = await this.providerAllowsDownload(dto.trackId, territory);
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
    const record = await this.prisma.downloadRecord.upsert({
      where: { userId_trackId: { userId, trackId: dto.trackId } },
      create: {
        userId,
        trackId: dto.trackId,
        expiresAt: offlineLeaseExpiresAt,
      },
      update: { expiresAt: offlineLeaseExpiresAt },
    });

    return {
      allowed: true,
      reason: 'OK',
      url: signed.url,
      recordId: record.id,
      expiresAt: signed.expiresAt,
      rightsExpiresAt: decision.expiresAt,
      offlineLeaseExpiresAt,
      attribution: decision.attribution,
    };
  }

  async revalidateOfflineLease(userId: string, trackId: string, territoryInput: string) {
    const territory = this.requireTerritory(territoryInput);
    const existing = await this.prisma.downloadRecord.findFirst({
      where: { userId, trackId, status: 'active' },
      select: { id: true },
    });
    if (!existing) return { allowed: false, reason: 'DOWNLOAD_NOT_FOUND' };

    const supported = await this.providerAllowsDownload(trackId, territory);
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
