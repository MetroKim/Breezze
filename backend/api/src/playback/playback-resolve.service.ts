import { Injectable, NotAcceptableException, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from './media-signer.service';
import { ProviderRegistry } from '../providers/provider-registry.service';
import { validateProviderAudioSource } from './provider-stream-guard';

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
    // A catalogue metadata record cannot authorize a Breezze-hosted media URL.
    // External providers must use the provider-specific resolver and deliver
    // their own authorized playback source; an internal rights row alone is
    // not proof that any audio bytes exist in Breezze's media storage.
    const track = await this.prisma.track.findUnique({
      where: { id: dto.trackId },
      select: { source: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');
    if (track.source === 'youtube_music' || track.source === 'deezer') {
      throw new NotAcceptableException('USE_PROVIDER_PLAYBACK_RESOLVER');
    }

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

    // Search metadata, previews and even upstream availability do not convey
    // full-audio rights. A canonical territory-aware permission is mandatory.
    const decision = await this.rights.decide({
      userId,
      trackId: dto.canonicalTrackId,
      action: 'stream.full',
      territory,
    });
    if (!decision.allowed || decision.previewOnly) {
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
    const result = await provider.resolvePlayback({
      providerTrackId: dto.providerTrackId,
      canonicalTrackId: dto.canonicalTrackId,
      territory,
      authorization: {
        action: 'stream.full',
        expiresAt: decision.expiresAt,
        attribution: decision.attribution ?? availability.attribution ?? null,
      },
    });
    if (result.kind === 'unsupported') {
      throw new NotAcceptableException(result.reason);
    }
    if (result.kind === 'error') {
      throw new ServiceUnavailableException(result.code);
    }

    // Fail closed before exposing the provider's bearer URL to Flutter.
    // Short leases are re-resolved, not cached or passed to the audio engine.
    const streamUrl = validateProviderAudioSource(result.value, decision.expiresAt);

    return {
      providerId: dto.providerId,
      providerTrackId: dto.providerTrackId,
      streamUrl: streamUrl.toString(),
      expiresAt: result.value.expiresAt,
      mimeType: result.value.mimeType,
      codec: result.value.codec,
      attribution: decision.attribution ??
        result.attribution ?? availability.attribution ?? null,
    };
  }
}
