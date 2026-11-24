import { Injectable, NotAcceptableException, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from './media-signer.service';
import { ProviderRegistry } from '../providers/provider-registry.service';

@Injectable()
export class PlaybackResolveService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
    private readonly signer: MediaSigner,
    private readonly providers: ProviderRegistry,
  ) {}

  private requireTerritory(edgeCountry?: string): string {
    const territory = edgeCountry?.trim().toUpperCase();
    if (!territory || !/^[A-Z]{2}$/.test(territory)) {
      throw new NotAcceptableException('PLAYBACK_TERRITORY_UNAVAILABLE');
    }
    return territory;
  }

  async resolve(
    userId: string | null,
    dto: { trackId: string; territory?: string; requestedQuality?: string },
    edgeCountry?: string,
  ) {
    const territory = this.requireTerritory(edgeCountry);
    const decision = await this.rights.decide({
      userId,
      trackId: dto.trackId,
      action: 'stream.full',
      territory,
    });
    if (!decision.allowed) {
      throw new NotAcceptableException(decision.reason);
    }
    // This endpoint creates a full-track URL. A preview grant is not a
    // full-stream entitlement; preview playback needs its own bounded URL.
    if (decision.previewOnly) {
      throw new NotAcceptableException('PREVIEW_ONLY');
    }
    const variant = decision.qualityRestriction ?? dto.requestedQuality ?? 'AAC_256';
    const signed = this.signer.createPlaybackUrl(
      dto.trackId,
      variant,
      decision.expiresAt,
    );
    return {
      trackId: dto.trackId,
      streamUrl: signed.url,
      expiresAt: signed.expiresAt,
      codec: variant === 'LOSSLESS' || variant === 'HI_RES' ? 'flac' : 'aac',
      attribution: decision.attribution,
      previewOnly: decision.previewOnly,
    };
  }

  async resolveProvider(
    userId: string,
    dto: {
      providerId: string;
      providerTrackId: string;
      canonicalTrackId: string;
      territory?: string;
    },
    edgeCountry?: string,
  ) {
    const territory = this.requireTerritory(edgeCountry);
    const canonicalTrack = await this.prisma.track.findUnique({
      where: { id: dto.canonicalTrackId },
    });
    if (
      !canonicalTrack ||
      canonicalTrack.source !== dto.providerId ||
      canonicalTrack.externalId !== 'bz:' + dto.providerId + ':' + dto.providerTrackId
    ) {
      throw new NotAcceptableException('PROVIDER_TRACK_MISMATCH');
    }

    const takedown = await this.prisma.contentTakedownCase.findFirst({
      where: { trackId: dto.canonicalTrackId, status: 'active' },
    });
    if (takedown) throw new NotAcceptableException('TAKEDOWN_ACTIVE');

    // A local full-stream permission is normally mandatory. Audius OML is
    // an exception only for recordings independently proven to be public,
    // free and third-party-API-streamable at this exact request. The metadata
    // lookup cannot create an entitlement: the signed-in session, mapping,
    // takedown and live provider permission must all pass.
    const decision = await this.rights.decide({
      userId,
      trackId: dto.canonicalTrackId,
      action: 'stream.full',
      territory,
    });
    if (decision.previewOnly ||
        (!decision.allowed &&
         (dto.providerId !== 'audius' ||
          !['NOT_AVAILABLE_IN_TERRITORY', 'NO_EXPLICIT_AUTHORIZATION']
            .includes(decision.reason)))) {
      // All other providers require a locally auditable full-track grant.
      // The Audius OML exemption only proceeds to a fresh live proof.
      throw new NotAcceptableException(
        decision.previewOnly ? 'PREVIEW_ONLY' : decision.reason,
      );
    }

    const provider = this.providers.get(dto.providerId);
    if (
      !provider ||
      !provider.capabilities.playback ||
      !provider.capabilities.availability
    ) {
      throw new NotFoundException('PLAYBACK_PROVIDER_UNAVAILABLE');
    }

    // External catalogues have their own current distribution controls.
    // Re-check them on every playback grant instead of trusting search-time
    // metadata or a client assertion. Fail closed before returning a URL.
    const availability = await provider.getAvailability(
      dto.providerTrackId,
      territory,
    );
    if (availability.kind === 'unsupported') {
      throw new NotAcceptableException(availability.reason);
    }
    if (availability.kind === 'error') {
      throw new ServiceUnavailableException(availability.code);
    }
    if (!availability.value.available) {
      throw new NotAcceptableException('PROVIDER_TRACK_UNAVAILABLE');
    }
    const publicAudiusGrant = dto.providerId === 'audius' &&
      process.env.BREEZZE_NONCOMMERCIAL === 'true' &&
      availability.attribution?.startsWith('Audius OML: ') === true;
    if (!decision.allowed && !publicAudiusGrant) {
      throw new NotAcceptableException(decision.reason);
    }

    const result = await provider.resolvePlayback({
      providerTrackId: dto.providerTrackId,
      canonicalTrackId: dto.canonicalTrackId,
      territory,
      authorization: {
        action: 'stream.full',
        expiresAt: decision.expiresAt,
        attribution: publicAudiusGrant
          ? availability.attribution!
          : decision.attribution ?? availability.attribution ?? null,
      },
    });
    if (result.kind === 'unsupported') {
      throw new NotAcceptableException(result.reason);
    }
    if (result.kind === 'error') {
      throw new ServiceUnavailableException(result.code);
    }

    // A provider adapter must never hand the client an insecure or expired URL.
    let streamUrl: URL;
    try {
      streamUrl = new URL(result.value.url);
    } catch {
      throw new ServiceUnavailableException('PROVIDER_RETURNED_INVALID_URL');
    }
    if (
      streamUrl.protocol !== 'https:' ||
      result.value.expiresAt.getTime() <= Date.now()
    ) {
      throw new ServiceUnavailableException('PROVIDER_RETURNED_INVALID_SOURCE');
    }
    // A provider URL whose validity extends beyond this recording's
    // explicit license window is not safe to hand out. Adapter metadata
    // cannot silently widen our canonical authorization interval.
    if (decision.expiresAt && result.value.expiresAt > decision.expiresAt) {
      throw new NotAcceptableException('PROVIDER_GRANT_OUTLIVES_RIGHTS');
    }

    return {
      providerId: dto.providerId,
      providerTrackId: dto.providerTrackId,
      streamUrl: streamUrl.toString(),
      expiresAt: result.value.expiresAt,
      mimeType: result.value.mimeType,
      codec: result.value.codec,
      // Preserve the artist's legally relevant OML notice. A provider
      // response's generic attribution must never override the terms and
      // source link from the live permission check.
      attribution: publicAudiusGrant
        ? availability.attribution!
        : result.attribution ?? availability.attribution ?? null,
    };
  }
}
