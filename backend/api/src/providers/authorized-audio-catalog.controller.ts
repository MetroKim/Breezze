import {
  Controller, Get, Headers, NotAcceptableException, Query, UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { OpenSubsonicAdapter } from './opensubsonic.adapter';

const OPEN_SUBSONIC_ID = /^bz:opensubsonic:([A-Za-z0-9_-]{1,128})$/;
const MAX_QUERY_LENGTH = 120;
const MAX_VISIBLE_CANDIDATES = 8;

/**
 * Only independently approved, territorially entitled catalog records can
 * appear as full-song search hits. A public provider's getSong/search endpoint
 * must NEVER expose all private library titles or imply playback permission.
 *
 * The actual session still rechecks rights, source identity and availability.
 * Search results are not stream URLs or bearer grants.
 */
@Controller('catalog/authorized-audio')
@UseGuards(JwtAuthGuard)
export class AuthorizedAudioCatalogController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
    private readonly opensubsonic: OpenSubsonicAdapter,
  ) {}

  @Get('search')
  async search(
    @Query('q') searchQuery: string | undefined,
    @Headers('x-breezze-country') edgeCountry?: string,
  ) {
    const query = (searchQuery ?? '').trim().replace(/\s+/g, ' ');
    if (query.length < 2 || query.length > MAX_QUERY_LENGTH) {
      return { items: [] };
    }
    const territory = edgeCountry?.trim().toUpperCase();
    if (!territory || !/^[A-Z]{2}$/.test(territory)) {
      throw new NotAcceptableException('AUDIO_TERRITORY_UNAVAILABLE');
    }
    // Misconfigured or uncontracted servers can never leak partner content.
    if (!this.opensubsonic.enabled) return { items: [] };

    const candidates = await this.prisma.track.findMany({
      where: {
        source: 'opensubsonic',
        OR: [
          { title: { contains: query, mode: 'insensitive' } },
          { artist: { name: { contains: query, mode: 'insensitive' } } },
        ],
      },
      include: { artist: true },
      orderBy: { title: 'asc' },
      take: 30,
    });

    // Filtering in Prisma first means an unentitled user never discovers
    // even the title of a private partner song through this endpoint.
    const approved = await this.rights.filterFullStream(
      candidates.map(track => track.id), territory,
    );
    const eligible = candidates.filter(track =>
      approved.has(track.id) &&
      typeof track.externalId === 'string' &&
      OPEN_SUBSONIC_ID.test(track.externalId) &&
      Number.isFinite(track.duration) && track.duration > 0,
    ).slice(0, MAX_VISIBLE_CANDIDATES);

    // A licensable DB row alone is not a playable file. Verify the currently
    // connected server has the exact song, in a bounded set of probes.
    const probed = await Promise.all(eligible.map(async track => {
      const providerTrackId = OPEN_SUBSONIC_ID.exec(track.externalId!)![1];
      try {
        const check = await this.opensubsonic.getAvailability(providerTrackId, territory);
        if (check.kind !== 'ok' || !check.value.available) return null;
        return {
          providerId: 'opensubsonic',
          providerTrackId,
          canonicalTrackId: track.id,
          title: track.title,
          artist: track.artist.name,
          durationSec: track.duration,
        };
      } catch {
        return null;
      }
    }));
    return { items: probed.filter((item): item is NonNullable<typeof item> =>
      item !== null) };
  }
}
