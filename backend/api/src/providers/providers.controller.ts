import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProviderRegistry } from './provider-registry.service';
import { YtMusicAdapter } from './ytmusic.adapter';
import { SpotifyAdapter } from './spotify.adapter';
import { ArtistCatalogService } from './artist-catalog.service';
import { OfficialYouTubeDataService } from './official-youtube-data.service';

// Read-only provider discovery and metadata endpoints.
@Controller('providers')
export class ProvidersController {
  constructor(
    private readonly registry: ProviderRegistry,
    private readonly youtubeMusic: YtMusicAdapter,
    private readonly officialYouTube: OfficialYouTubeDataService,
    private readonly spotify: SpotifyAdapter,
    private readonly artistCatalog: ArtistCatalogService,
  ) {}

  @Get()
  list() {
    return this.registry.list();
  }

  @Get('search')
  @UseGuards(JwtAuthGuard)
  searchAll(@Query('q') q: string) {
    return this.registry.searchAll(q ?? '');
  }

  // Spotify-first and Deezer-fallback audio discovery, with a single
  // matched recording list. YouTube video discovery is separate.
  @Get('music/search')
  @UseGuards(JwtAuthGuard)
  searchMusic(@Query('q') q: string) {
    return this.registry.searchMusic(q ?? '');
  }

  // Artist identity and profile remain Spotify-led. Optional, exact-name
  // Deezer supplements fill missing sections only when approved.
  @Get('spotify/artists/search')
  @UseGuards(JwtAuthGuard)
  searchSpotifyArtists(@Query('q') q: string) {
    return this.spotify.searchArtists(q ?? '');
  }

  @Get('spotify/artists/:artistId')
  @UseGuards(JwtAuthGuard)
  spotifyArtistPage(@Param('artistId') artistId: string) {
    return this.artistCatalog.getArtistPage(artistId);
  }

  @Get('spotify/albums/:albumId')
  @UseGuards(JwtAuthGuard)
  spotifyAlbumPage(@Param('albumId') albumId: string) {
    return this.spotify.getAlbumPage(albumId);
  }

  // Google official video discovery. No YouTube audio extraction endpoint.
  @Get('youtube/videos/search')
  @UseGuards(JwtAuthGuard)
  searchOfficialYouTubeVideos(@Query('q') q: string, @Query('limit') limit?: string) {
    return this.officialYouTube.searchMusicVideos(q ?? '', limit === undefined ? 20 : Number(limit));
  }

  @Get('youtube/videos/:videoId')
  @UseGuards(JwtAuthGuard)
  officialYouTubeVideoDetails(@Param('videoId') videoId: string) {
    return this.officialYouTube.getVideo(videoId);
  }

  @Get('youtube_music/artists/search')
  searchYoutubeMusicArtists(@Query('q') q: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.searchArtists(q ?? '');
  }

  @Get('youtube_music/artists/:artistId')
  getYoutubeMusicArtist(@Param('artistId') artistId: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getArtist(artistId);
  }

  @Get('youtube_music/charts')
  getYoutubeMusicCharts(@Query('country') country: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getCharts(country || 'ZZ');
  }

  @Get('youtube_music/watch-queue/:videoId')
  getYoutubeMusicWatchQueue(
    @Param('videoId') videoId: string,
    @Query('limit') limit: string | undefined,
  ) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    const parsedLimit = limit === undefined ? 20 : Number(limit);
    return this.youtubeMusic.getWatchQueue(videoId, parsedLimit);
  }

  // All these routes call the private ytmusicapi service for public catalog
  // metadata. None return media bytes, signed streaming URLs or download grants.
  @Get('youtube_music/suggestions')
  getYoutubeMusicSuggestions(@Query('q') query: string, @Query('limit') limit?: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getSuggestions(query ?? '', limit === undefined ? 10 : Number(limit));
  }

  @Get('youtube_music/albums/:albumId')
  getYoutubeMusicAlbum(@Param('albumId') albumId: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getAlbum(albumId);
  }

  @Get('youtube_music/playlists/:playlistId')
  getYoutubeMusicPlaylist(@Param('playlistId') playlistId: string, @Query('limit') limit?: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getPlaylist(playlistId, limit === undefined ? 50 : Number(limit));
  }

  @Get('youtube_music/moods')
  getYoutubeMusicMoods() {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getMoods();
  }

  @Get('youtube_music/moods/playlists')
  getYoutubeMusicMoodPlaylists(@Query('params') params: string, @Query('limit') limit?: string) {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getMoodPlaylists(params ?? '', limit === undefined ? 20 : Number(limit));
  }

  @Get('youtube_music/explore')
  getYoutubeMusicExplore() {
    if (!this.youtubeMusic.enabled) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    return this.youtubeMusic.getExplore();
  }

  @Get(':id/tracks/:trackId')
  getTrack(@Param('id') id: string, @Param('trackId') trackId: string) {
    if (id === 'breezze_internal') return { kind: 'unsupported', reason: 'USE_RIGHTS_AWARE_CATALOG_ENDPOINT' };
    const adapter = this.registry.get(id);
    if (!adapter) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    if (!adapter.capabilities.metadata) {
      return { kind: 'unsupported', reason: 'METADATA_NOT_CAPABLE' };
    }
    return adapter.getTrack(trackId);
  }

  @Get(':id/search')
  @UseGuards(JwtAuthGuard)
  search(@Param('id') id: string, @Query('q') q: string) {
    const adapter = this.registry.get(id);
    if (!adapter) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    if (!adapter.capabilities.search) {
      return { kind: 'unsupported', reason: 'SEARCH_NOT_CAPABLE' };
    }
    return adapter.search(q ?? '');
  }
}
