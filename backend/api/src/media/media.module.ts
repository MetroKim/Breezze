import { Module } from '@nestjs/common';
import { PlaybackModule } from '../playback/playback.module';
import { MediaController } from './media.controller';
import { MediaService } from './media.service';

@Module({
  imports: [PlaybackModule],
  controllers: [MediaController],
  providers: [MediaService],
  exports: [MediaService],
})
export class MediaModule {}
