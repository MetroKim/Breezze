import { Controller, Get, Param, Query, ServiceUnavailableException, BadRequestException } from '@nestjs/common';
import { DiscoveryService } from './discovery.service';

@Controller('discovery')
export class DiscoveryController {
  constructor(private readonly discovery: DiscoveryService) {}

  @Get('charts/songs')
  async songsChart(@Query('country') country?: string) {
    try { return await this.discovery.songsChart(country); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple Music RSS' }); }
  }

  @Get('releases/albums')
  async newReleases(@Query('country') country?: string) {
    try { return await this.discovery.newReleases(country); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple Music RSS' }); }
  }

  @Get('tracks/search')
  async searchTracks(@Query('q') query = '') {
    try { return await this.discovery.searchTracks(query); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple iTunes Search API' }); }
  }

  @Get('artists/search')
  async searchArtists(@Query('q') query = '') {
    try { return await this.discovery.searchArtists(query); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple iTunes Search API' }); }
  }

  @Get('artists/:artistId/albums')
  async artistAlbums(@Param('artistId') artistId: string) {
    try { return await this.discovery.artistAlbums(artistId); }
    catch (error) {
      if (error instanceof Error && error.message.startsWith('INVALID_')) throw new BadRequestException(error.message);
      throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple iTunes Search API' });
    }
  }

  @Get('albums/:albumId/tracks')
  async albumTracks(@Param('albumId') albumId: string) {
    try { return await this.discovery.albumTracks(albumId); }
    catch (error) {
      if (error instanceof Error && error.message.startsWith('INVALID_')) throw new BadRequestException(error.message);
      throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple iTunes Search API' });
    }
  }
}
