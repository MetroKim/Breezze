import { Controller, Get, Param, Query, ServiceUnavailableException, BadRequestException } from '@nestjs/common';
import { DiscoveryService } from './discovery.service';

@Controller('discovery')
export class DiscoveryController {
  constructor(private readonly discovery: DiscoveryService) {}

  @Get('charts/daily-top-100')
  async dailyTop100(@Query('country') country?: string) {
    try { return await this.discovery.dailyTop100(country); }
    catch (error) {
      if (error instanceof Error && error.message.endsWith('_NOT_CONFIGURED')) {
        throw new ServiceUnavailableException({ code: 'PROVIDER_NOT_CONFIGURED', provider: 'Apple Music API' });
      }
      throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple Music API' });
    }
  }

  @Get('charts/songs')
  async songsChart(@Query('country') country?: string) {
    try { return await this.discovery.songsChart(country); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple Music RSS' }); }
  }

  @Get('releases/songs')
  async latestSongs(@Query('country') country?: string) {
    try { return await this.discovery.recentChartReleases('songs', country); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple Music RSS' }); }
  }

  @Get('releases/albums')
  async newReleases(@Query('country') country?: string) {
    try { return await this.discovery.newReleases(country); }
    catch { throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'Apple Music RSS' }); }
  }

  @Get('songs/:id/music-video')
  async musicVideoForSong(@Param('id') id: string) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(id)) throw new BadRequestException('INVALID_SONG_ID');
    try { return await this.discovery.musicVideoForSong(id); }
    catch { throw new ServiceUnavailableException('YTMUSIC_COUNTERPART_UNAVAILABLE'); }
  }

  @Get('videos')
  async musicVideos(@Query('q') query = '') {
    try { return await this.discovery.musicVideos(query); }
    catch (error) {
      if (error instanceof Error && error.message.endsWith('_NOT_CONFIGURED')) {
        throw new ServiceUnavailableException({ code: 'PROVIDER_NOT_CONFIGURED', provider: 'YouTube Music via ytmusicapi' });
      }
      throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'YouTube Music via ytmusicapi' });
    }
  }

  @Get('concerts')
  async concerts(@Query('country') country = 'TZ', @Query('city') city?: string) {
    try { return await this.discovery.concerts(country, city); }
    catch (error) {
      if (error instanceof Error && error.message.endsWith('_NOT_CONFIGURED')) {
        throw new ServiceUnavailableException({ code: 'PROVIDER_NOT_CONFIGURED', provider: 'JamBase Data' });
      }
      throw new ServiceUnavailableException({ code: 'DISCOVERY_SOURCE_UNAVAILABLE', source: 'JamBase Data' });
    }
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
