import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class PlaylistsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, name: string) {
    return this.prisma.playlist.create({
      data: { userId, name },
    });
  }

  async list(userId: string) {
    return this.prisma.playlist.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async get(userId: string, playlistId: string) {
    const playlist = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId },
      include: { items: { orderBy: { position: 'asc' } } },
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
