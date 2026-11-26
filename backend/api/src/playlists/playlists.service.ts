import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class PlaylistsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, name: string, id?: string) {
    // A client-generated UUID makes offline creation replayable. The owner
    // scope is checked even when a conflicting identifier already exists.
    try {
      return await this.prisma.playlist.create({
        data: { userId, name, ...(id ? { id } : {}) },
      });
    } catch (error) {
      if (id && (error as { code?: string } | null)?.code === 'P2002') {
        const owned = await this.prisma.playlist.findFirst({
          where: { id, userId },
        });
        if (owned) return owned; // Retried offline creation; idempotent.
        throw new ConflictException('PLAYLIST_ID_CONFLICT');
      }
      throw error;
    }
  }

  async list(userId: string) {
    // A single owner-filtered snapshot hydrates tracks on another device
    // without an N+1 fetch for each playlist.
    return this.prisma.playlist.findMany({
      where: { userId },
      orderBy: [{ isPinned: 'desc' }, { createdAt: 'desc' }],
      include: {
        items: {
          orderBy: { position: 'asc' },
          include: {
            track: {
              include: { artist: true, album: true },
            },
          },
        },
      },
    });
  }

  async get(userId: string, playlistId: string) {
    const playlist = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId },
      include: {
        items: {
          orderBy: { position: 'asc' },
          include: {
            track: {
              include: { artist: true, album: true },
            },
          },
        },
      },
    });
    if (!playlist) throw new NotFoundException('PLAYLIST_NOT_FOUND');
    return playlist;
  }

  async rename(userId: string, playlistId: string, name: string) {
    const updated = await this.prisma.playlist.updateMany({
      where: { id: playlistId, userId },
      data: { name },
    });
    if (updated.count !== 1) throw new NotFoundException('PLAYLIST_NOT_FOUND');
    return this.prisma.playlist.findFirst({
      where: { id: playlistId, userId },
    });
  }

  async setPinned(userId: string, playlistId: string, pinned: boolean) {
    const updated = await this.prisma.playlist.updateMany({
      where: { id: playlistId, userId },
      data: { isPinned: pinned },
    });
    if (updated.count !== 1) throw new NotFoundException('PLAYLIST_NOT_FOUND');
    return this.prisma.playlist.findFirst({
      where: { id: playlistId, userId },
    });
  }

  /**
   * Persist only a small validated PNG thumbnail in the playlist owner's
   * existing row. Client credentials, external provider media, and storage
   * service-role keys never enter this endpoint. Null restores the 2x2 cover.
   */
  async setCover(userId: string, playlistId: string, coverPngBase64: string | null) {
    if (coverPngBase64 !== null) {
      if (
        typeof coverPngBase64 !== 'string' ||
        !coverPngBase64 || coverPngBase64.length > 350000 ||
        coverPngBase64.length % 4 !== 0 ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(coverPngBase64)
      ) {
        throw new BadRequestException('PLAYLIST_COVER_INVALID_ENCODING');
      }
      const png = Buffer.from(coverPngBase64, 'base64');
      const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
      if (
        png.length < 45 || png.length > 256000 ||
        !png.subarray(0, 8).equals(signature) ||
        png.toString('ascii', 12, 16) !== 'IHDR'
      ) {
        throw new BadRequestException('PLAYLIST_COVER_INVALID_PNG');
      }
      const width = png.readUInt32BE(16);
      const height = png.readUInt32BE(20);
      if (width < 1 || height < 1 || width > 512 || height > 512) {
        throw new BadRequestException('PLAYLIST_COVER_INVALID_DIMENSIONS');
      }
    }
    const result = await this.prisma.playlist.updateMany({
      where: { id: playlistId, userId },
      data: { coverPngBase64 },
    });
    if (result.count !== 1) throw new NotFoundException('PLAYLIST_NOT_FOUND');
    return { id: playlistId, coverPngBase64 };
  }

  async delete(userId: string, playlistId: string) {
    const deleted = await this.prisma.playlist.deleteMany({
      where: { id: playlistId, userId },
    });
    if (deleted.count !== 1) throw new NotFoundException('PLAYLIST_NOT_FOUND');
    return { deleted: true };
  }

  async addTrack(userId: string, playlistId: string, trackId: string) {
    return this.prisma.$transaction(async (tx) => {
      // Serialize additions to the same playlist. Without this row lock,
      // concurrent requests can calculate the same next position.
      const owned = await tx.$queryRaw<Array<{ id: string }>>`
        SELECT "id"
        FROM "Playlist"
        WHERE "id" = ${playlistId} AND "userId" = ${userId}
        FOR UPDATE
      `;
      if (owned.length === 0) throw new NotFoundException('PLAYLIST_NOT_FOUND');

      const track = await tx.track.findUnique({
        where: { id: trackId },
        select: { id: true },
      });
      if (!track) throw new NotFoundException('TRACK_NOT_FOUND');

      // Treat a repeated add as idempotent rather than returning a database
      // uniqueness error to a client retrying after a network timeout.
      const existing = await tx.playlistItem.findFirst({
        where: { playlistId, trackId },
      });
      if (existing) return existing;

      // max + 1 remains correct after removals create gaps; count() could
      // reuse an occupied position and produce an unstable queue order.
      const aggregate = await tx.playlistItem.aggregate({
        where: { playlistId },
        _max: { position: true },
      });
      const position = (aggregate._max.position ?? -1) + 1;

      return tx.playlistItem.create({
        data: { playlistId, trackId, position },
      });
    });
  }

  async reorderTracks(
    userId: string,
    playlistId: string,
    orderedTrackIds: string[],
  ) {
    return this.prisma.$transaction(async (tx) => {
      const owned = await tx.$queryRaw<Array<{ id: string }>>`
        SELECT "id"
        FROM "Playlist"
        WHERE "id" = ${playlistId} AND "userId" = ${userId}
        FOR UPDATE
      `;
      if (owned.length === 0) throw new NotFoundException('PLAYLIST_NOT_FOUND');

      const current = await tx.playlistItem.findMany({
        where: { playlistId },
        select: { trackId: true },
      });
      const currentIds = new Set(current.map((item) => item.trackId));
      const requestedIds = new Set(orderedTrackIds);
      if (
        currentIds.size !== requestedIds.size ||
        currentIds.size !== orderedTrackIds.length ||
        [...currentIds].some((id) => !requestedIds.has(id))
      ) {
        throw new BadRequestException('PLAYLIST_ORDER_MISMATCH');
      }

      for (const [position, trackId] of orderedTrackIds.entries()) {
        await tx.playlistItem.updateMany({
          where: { playlistId, trackId },
          data: { position },
        });
      }
      return { reordered: true, count: orderedTrackIds.length };
    });
  }

  async removeTrack(userId: string, playlistId: string, trackId: string) {
    await this.assertOwned(userId, playlistId);
    await this.prisma.playlistItem.deleteMany({
      where: { playlistId, trackId },
    });
    return { removed: true };
  }

  private async assertOwned(userId: string, playlistId: string) {
    const owned = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId },
    });
    if (!owned) throw new NotFoundException('PLAYLIST_NOT_FOUND');
  }
}
