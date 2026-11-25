import { Module } from '@nestjs/common';
import { RightsModule } from '../rights/rights.module';
import { ProvidersModule } from '../providers/providers.module';
import { DownloadsController } from './downloads.controller';
import { VideoAssetsController } from './video-assets.controller';
import { VideoAssetsService } from './video-assets.service';
import { DownloadsService } from './downloads.service';
import { MediaSigner } from '../playback/media-signer.service';
import { MediaSignerFactory } from '../playback/media-signer.factory';

@Module({
  imports: [RightsModule, ProvidersModule],
  controllers: [DownloadsController, VideoAssetsController],
  providers: [
    DownloadsService,
    VideoAssetsService,
    MediaSignerFactory,
    {
      provide: MediaSigner,
      useFactory: (factory: MediaSignerFactory) => factory.create(),
      inject: [MediaSignerFactory],
    },
  ],
})
export class DownloadsModule {}
