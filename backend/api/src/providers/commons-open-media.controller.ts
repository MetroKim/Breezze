import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CommonsOpenMediaService } from './commons-open-media.service';

/**
 * On-demand discovery and file-rights lookup. No Breezze-hosted media,
 * downloaded file or permanently cached byte stream is created.
 * Client must retain and display the creator/source/license attribution
 * alongside online playback AND any device-saved file.
 */
@Controller('providers/open-media/commons')
@UseGuards(JwtAuthGuard)
export class CommonsOpenMediaController {
  constructor(private readonly commons: CommonsOpenMediaService) {}

  @Get('search')
  search(@Query('q') query: string | undefined, @Query('kind') kind: string | undefined) {
    return this.commons.search(query, kind);
  }

  @Get('resolve')
  resolve(@Query('title') title: string | undefined, @Query('kind') kind: string | undefined) {
    return this.commons.resolve(title, kind);
  }
}
