import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { VideoService } from './video.service';

@Controller('video')
@UseGuards(JwtAuthGuard)
export class VideoController {
  constructor(private readonly video: VideoService) {}

  @Get('search')
  search(@Query('q') q: string) {
    return this.video.search(q ?? '');
  }

  @Get(':id')
  get(@Param('id') id: string) {
    return this.video.get(id);
  }
}
