import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { ProviderRegistry } from '../providers/provider-registry.service';
import { RightsDecisionService } from '../rights/rights-decision.service';

@Injectable()
export class SearchService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly providers: ProviderRegistry,
    private readonly rights: RightsDecisionService,
  ) {}

  async search(query: string, territory?: string) {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) {
      return {
        tracks: [],
        artists: [],
        albums: [],
        externalTracks: [],
        externalProviderStatus: 'skipped',
        providerStatuses: [],
      };
    }

    // Search every enabled provider that explicitly advertises catalogue
    // search. A provider's playback capability is deliberately irrelevant
    // here: metadata results must never be treated as playable queue items.
    const searchableProviders = this.providers.list()
      .filter((provider) => provider.capabilities.search && provider.providerId !== 'breezze_internal')
      .map((provider) => this.providers.get(provider.providerId))
      .filter((provider) => provider !== undefined);

    const [tracks, artists, albums, providerResults] = await Promise.all([
      this.prisma.track.findMany({
        where: { title: { contains: q, mode: 'insensitive' } },
        include: { artist: true, album: true },
        take: 20,
      }),
      this.prisma.artist.findMany({
        where: { name: { contains: q, mode: 'insensitive' } },
        include: { tracks: { select: { id: true }, take: 100 } },
        take: 5,
      }),
      this.prisma.album.findMany({
        where: { title: { contains: q, mode: 'insensitive' } },
        include: { tracks: { select: { id: true }, take: 100 } },
        take: 5,
      }),
      Promise.all(searchableProviders.map(async (provider) => ({
        providerId: provider.providerId,
        result: await provider.search(q),
      }))),
    ]);

    const metadataTrackIds = [...new Set([
      ...tracks.map((track) => track.id),
      ...artists.flatMap((artist) => artist.tracks.map((track) => track.id)),
      ...albums.flatMap((album) => album.tracks.map((track) => track.id)),
    ])];
    const visibleTrackIds = await this.rights.filterMetadataDisplay(
      metadataTrackIds,
      territory?.trim().toUpperCase() ?? '',
    );
    const visibleTracks = tracks.filter((track) => visibleTrackIds.has(track.id));
    const visibleArtists = artists
      .filter((artist) => artist.tracks.some((track) => visibleTrackIds.has(track.id)))
      .map(({ tracks: _tracks, ...artist }) => artist);
    const visibleAlbums = albums
      .filter((album) => album.tracks.some((track) => visibleTrackIds.has(track.id)))
      .map(({ tracks: _tracks, ...album }) => album);

    const externalTracks = providerResults.flatMap(({ providerId, result }) =>
      result.kind === 'ok'
        ? result.value.map((track) => ({
            ...track,
            providerId,
            capabilities: this.providers.get(providerId)?.capabilities,
            attribution: result.attribution,
          }))
        : [],
    );
    const providerStatuses = providerResults.map(({ providerId, result }) => ({
      providerId,
      status: result.kind,
      ...(result.kind === 'unsupported' ? { reason: result.reason } : {}),
      ...(result.kind === 'error'
        ? { code: result.code, retryable: result.retryable }
        : {}),
    }));

    return {
      tracks: visibleTracks,
      artists: visibleArtists,
      albums: visibleAlbums,
      externalTracks,
      // Keep the legacy aggregate field while clients migrate to the
      // provider-specific status array.
      externalProviderStatus: providerStatuses.some((item) => item.status === 'ok')
        ? 'ok'
        : providerStatuses.some((item) => item.status === 'error')
          ? 'error'
          : 'unsupported',
      providerStatuses,
    };
  }
}
