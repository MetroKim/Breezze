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
    await this.assertOwned(userId, playlistId);
    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { id: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');
    const count = await this.prisma.playlistItem.count({
      where: { playlistId },
    });
    return this.prisma.playlistItem.create({
      data: { playlistId, trackId, position: count },
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
