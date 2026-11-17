import { Controller, Get, NotFoundException, Param } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Controller('catalog')
export class CatalogController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('songs/:id')
  async song(@Param('id') id: string) {
    const track = await this.prisma.track.findUnique({
      where: { id },
      include: { artist: true, album: true },
    });
    if (!track) throw new NotFoundException('TRACK_NOT_FOUND');
    return track;
  }

  @Get('albums/:id')
  async album(@Param('id') id: string) {
    const album = await this.prisma.album.findUnique({
      where: { id },
      include: { tracks: true, artist: true },
    });
    if (!album) throw new NotFoundException('ALBUM_NOT_FOUND');
    return album;
  }

  @Get('artists/:id')
  async artist(@Param('id') id: string) {
    const artist = await this.prisma.artist.findUnique({
      where: { id },
      include: { albums: true, tracks: true },
    });
    if (!artist) throw new NotFoundException('ARTIST_NOT_FOUND');
    return artist;
  }
}
