import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';

// Canonical catalogue reads are territory- and takedown-aware. Public edge
// caching is partitioned by the trusted Cloudflare country header.
@Injectable()
export class CatalogService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
  ) {}

  async resolve(dto: {
    externalId: string;
    source: string;
    title: string;
    artistName: string;
    durationSec: number;
  }) {
    const artist = await this.prisma.artist.upsert({
      where: { name: dto.artistName },
      create: { name: dto.artistName },
      update: {},
    });

    return this.prisma.track.upsert({
      where: { externalId: dto.externalId },
      create: {
        externalId: dto.externalId,
        source: dto.source,
        title: dto.title,
        artistId: artist.id,
        duration: Math.round(dto.durationSec),
      },
      update: {},
    });
  }

  private async filterVisibleTracks<T extends { id: string }>(
    tracks: T[],
    territory: string,
  ): Promise<T[]> {
    const decisions = await Promise.all(tracks.map((track) =>
      this.rights.decide({
        userId: null,
        trackId: track.id,
        action: 'metadata.display',
        territory,
      }),
    ));
    return tracks.filter((_track, index) => decisions[index].allowed);
  }

  async song(id: string, territory: string) {
    const track = await this.prisma.track.findUnique({
      where: { id },
      include: { artist: true, album: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');
    const [visible] = await this.filterVisibleTracks([track], territory);
    if (!visible) throw new NotFoundException('TRACK_NOT_FOUND');
    return visible;
  }

  async album(id: string, territory: string) {
    const album = await this.prisma.album.findUnique({
      where: { id },
      include: { tracks: true, artist: true },
    });
    if (!album) throw new NotFoundException('ALBUM_NOT_FOUND');
    const tracks = await this.filterVisibleTracks(album.tracks, territory);
    if (tracks.length === 0) throw new NotFoundException('ALBUM_NOT_FOUND');
    return { ...album, tracks };
  }

  async artist(id: string, territory: string) {
    const artist = await this.prisma.artist.findUnique({
      where: { id },
      include: { albums: { include: { tracks: true } }, tracks: true },
    });
    if (!artist) throw new NotFoundException('ARTIST_NOT_FOUND');

    const visibleTracks = await this.filterVisibleTracks(artist.tracks, territory);
    const visibleIds = new Set(visibleTracks.map((track) => track.id));
    const albums = artist.albums
      .map((album) => ({
        ...album,
        tracks: album.tracks.filter((track) => visibleIds.has(track.id)),
      }))
      .filter((album) => album.tracks.length > 0);
    if (visibleTracks.length === 0) throw new NotFoundException('ARTIST_NOT_FOUND');
    return { ...artist, tracks: visibleTracks, albums };
  }
}
