import {
  Controller, Delete, Get, Headers, Param, ParseUUIDPipe, Post, UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { VideoAssetsService } from './video-assets.service';

/** Only authenticated, rights-gated Breezze-owned videos. */
@Controller('videos')
@UseGuards(JwtAuthGuard)
export class VideoAssetsController {
  constructor(private readonly videos: VideoAssetsService) {}

  @Get('catalog')
  catalog(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') territory?: string,
  ) {
    return this.videos.catalog(userId, territory);
  }

  @Get('downloads')
  listDownloads(@CurrentUser() userId: string) {
    return this.videos.list(userId);
  }

  @Get(':assetId/playback')
  playback(
    @CurrentUser() userId: string,
    @Param('assetId', new ParseUUIDPipe()) assetId: string,
    @Headers('x-breezze-country') territory?: string,
  ) {
    return this.videos.playback(userId, assetId, territory);
  }

  @Post(':assetId/download')
  download(
    @CurrentUser() userId: string,
    @Param('assetId', new ParseUUIDPipe()) assetId: string,
    @Headers('x-breezze-country') territory?: string,
  ) {
    return this.videos.authorizeDownload(userId, assetId, territory);
  }

  @Post(':assetId/download/revalidate')
  revalidate(
    @CurrentUser() userId: string,
    @Param('assetId', new ParseUUIDPipe()) assetId: string,
    @Headers('x-breezze-country') territory?: string,
  ) {
    return this.videos.revalidate(userId, assetId, territory);
  }

  @Delete(':assetId/download')
  remove(
    @CurrentUser() userId: string,
    @Param('assetId', new ParseUUIDPipe()) assetId: string,
  ) {
    return this.videos.remove(userId, assetId);
  }
}
