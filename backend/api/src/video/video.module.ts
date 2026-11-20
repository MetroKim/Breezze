import { Module } from '@nestjs/common';
import { YoutubeMetadataAdapter } from '../providers/youtube-metadata.adapter';
import { VideoController } from './video.controller';
import { VideoService } from './video.service';

@Module({
  controllers: [VideoController],
  providers: [VideoService, YoutubeMetadataAdapter],
})
export class VideoModule {}
