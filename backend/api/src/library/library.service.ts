import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class LibraryService {
  constructor(private readonly prisma: PrismaService) {}

  async listFollowedArtists(userId: string) {
    const items = await this.prisma.userFollowedArtist.findMany({
      where: { userId },
      orderBy: [{ isPinned: 'desc' }, { followedAt: 'desc' }, { artistKey: 'asc' }],
      select: { artistKey: true, displayName: true, isPinned: true, followedAt: true },
    });
    return { items };
  }

  async artistStatus(userId: string, artistKey: string) {
    const row = await this.prisma.userFollowedArtist.findUnique({
      where: { userId_artistKey: { userId, artistKey } },
    });
    return { following: row !== null, isPinned: row?.isPinned ?? false };
  }

  async setFollowing(
    userId: string, artistKey: string, following: boolean, displayName?: string,
  ) {
    if (following) {
      const name = displayName?.trim() || null;
      await this.prisma.userFollowedArtist.upsert({
        where: { userId_artistKey: { userId, artistKey } },
        create: { userId, artistKey, displayName: name },
        update: name === null ? {} : { displayName: name },
      });
    } else {
      await this.prisma.userFollowedArtist.deleteMany({
        where: { userId, artistKey },
      });
    }
    return { following };
  }

  async setArtistPinned(userId: string, artistKey: string, pinned: boolean) {
    const updated = await this.prisma.userFollowedArtist.updateMany({
      where: { userId, artistKey },
      data: { isPinned: pinned },
    });
    if (updated.count !== 1) {
      throw new NotFoundException('ARTIST_NOT_FOLLOWED');
    }
    return { following: true, isPinned: pinned };
  }

  private static readonly savedAlbumSource = 'apple_itunes';

  private trustedCatalogUrl(value: string | undefined): string | null {
    if (!value) return null;
    try {
      const url = new URL(value);
      if (url.protocol !== 'https:' || url.username || url.password ||
          !['music.apple.com', 'itunes.apple.com'].includes(url.hostname)) {
        throw new Error('Invalid catalog hostname');
      }
      return url.toString();
    } catch (_) {
      throw new BadRequestException('SAVED_ALBUM_CATALOG_URL_INVALID');
    }
  }

  private trustedArtworkUrl(value: string | undefined): string | null {
    if (!value) return null;
    try {
      const url = new URL(value);
      if (url.protocol !== 'https:' || url.username || url.password ||
          !(url.hostname === 'mzstatic.com' || url.hostname.endsWith('.mzstatic.com'))) {
        throw new Error('Invalid artwork hostname');
      }
      return url.toString();
    } catch (_) {
      throw new BadRequestException('SAVED_ALBUM_ARTWORK_URL_INVALID');
    }
  }

  async listSavedAlbums(userId: string, cursor?: string) {
    if (cursor) {
      const previous = await this.prisma.userSavedCatalogAlbum.findFirst({
        where: { userId, id: cursor },
        select: { id: true },
      });
      if (!previous) throw new BadRequestException('SAVED_ALBUM_CURSOR_INVALID');
    }
    const rows = await this.prisma.userSavedCatalogAlbum.findMany({
      where: { userId, source: LibraryService.savedAlbumSource },
      orderBy: [{ isPinned: 'desc' }, { savedAt: 'desc' }, { id: 'desc' }],
      take: 101,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select: {
        id: true,
        source: true,
        externalAlbumId: true,
        title: true,
        artist: true,
        artworkUrl: true,
        catalogUrl: true,
        genres: true,
        isCompilation: true,
        isPinned: true,
        savedAt: true,
        updatedAt: true,
      },
    });
    const items = rows.slice(0, 100);
    return {
      items,
      nextCursor: rows.length > 100 ? items[items.length - 1].id : null,
    };
  }

  async upsertSavedAlbum(
    userId: string,
    dto: {
      externalAlbumId: string;
      title: string;
      artist: string;
      artworkUrl?: string;
      catalogUrl?: string;
      genres?: string[];
      isCompilation?: boolean;
      isPinned?: boolean;
    },
  ) {
    const source = LibraryService.savedAlbumSource;
    const externalAlbumId = dto.externalAlbumId.trim();
    if (!/^[0-9]{1,20}$/.test(externalAlbumId) ||
        !dto.title.trim() || !dto.artist.trim()) {
      throw new BadRequestException('SAVED_ALBUM_INVALID');
    }
    const genres = [...new Set((dto.genres ?? [])
      .map((genre) => genre.trim())
      .filter(Boolean))].slice(0, 10);
    const payload = {
      title: dto.title.trim(),
      artist: dto.artist.trim(),
      artworkUrl: this.trustedArtworkUrl(dto.artworkUrl),
      catalogUrl: this.trustedCatalogUrl(dto.catalogUrl),
      genres,
      isCompilation: dto.isCompilation === true,
    };
    return this.prisma.userSavedCatalogAlbum.upsert({
      where: {
        userId_source_externalAlbumId: { userId, source, externalAlbumId },
      },
      create: { userId, source, externalAlbumId, ...payload, isPinned: dto.isPinned === true },
      update: {
        ...payload,
        ...(dto.isPinned === undefined ? {} : { isPinned: dto.isPinned }),
      },
      select: {
        id: true,
        source: true,
        externalAlbumId: true,
        title: true,
        artist: true,
        artworkUrl: true,
        catalogUrl: true,
        genres: true,
        isCompilation: true,
        isPinned: true,
        savedAt: true,
        updatedAt: true,
      },
    });
  }

  async removeSavedAlbum(userId: string, externalAlbumId: string) {
    if (!/^[0-9]{1,20}$/.test(externalAlbumId)) {
      throw new BadRequestException('SAVED_ALBUM_INVALID');
    }
    await this.prisma.userSavedCatalogAlbum.deleteMany({
      where: {
        userId,
        source: LibraryService.savedAlbumSource,
        externalAlbumId,
      },
    });
    return { removed: true };
  }

  async listFavorites(userId: string) {
    return this.prisma.favorite.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        trackId: true,
        createdAt: true,
        track: {
          select: {
            id: true,
            title: true,
            duration: true,
            artist: { select: { name: true } },
          },
        },
      },
    });
  }

  async addFavorite(userId: string, trackId: string) {
    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { id: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');

    return this.prisma.favorite.upsert({
      where: { userId_trackId: { userId, trackId } },
      create: { userId, trackId },
      update: {},
    });
  }

  async removeFavorite(userId: string, trackId: string) {
    await this.prisma.favorite.deleteMany({
      where: { userId, trackId },
    });
    return { removed: true };
  }
}
