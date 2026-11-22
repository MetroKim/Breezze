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

  private async providerAllowsDownload(
    trackId: string,
    territory: string,
  ): Promise<boolean> {
    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { id: true, source: true, externalId: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');

    // Breezze-hosted assets are authorized by the rights engine and signed
    // media service. External providers must explicitly support downloads.
    if (!track.source || track.source === 'breezze_internal') return true;

    const provider = this.providers.get(track.source);
    if (
      !provider ||
      !provider.capabilities.download ||
      !provider.capabilities.availability
    ) {
      return false;
    }

    const externalPrefix = `bz:${track.source}:`;
    if (!track.externalId?.startsWith(externalPrefix)) return false;
    const providerTrackId = track.externalId.slice(externalPrefix.length);
    if (!providerTrackId) return false;

    const availability = await provider.getAvailability(providerTrackId, territory);
    return availability.kind === 'ok' && availability.value.available;
  }

  async authorizeAndRecord(
    userId: string,
    dto: { trackId: string; territory: string },
  ) {
    const supported = await this.providerAllowsDownload(dto.trackId, dto.territory);
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
      territory: dto.territory,
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

  async revalidateOfflineLease(userId: string, trackId: string, territory: string) {
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
