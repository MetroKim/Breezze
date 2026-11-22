import { Module } from '@nestjs/common';
import { RightsModule } from '../rights/rights.module';
import { PlaybackResolveService } from './playback-resolve.service';
import { PlaybackController } from './playback.controller';
import { MediaSigner } from './media-signer.service';
import { MediaSignerFactory } from './media-signer.factory';
import { ProvidersModule } from '../providers/providers.module';

@Module({
  imports: [RightsModule, ProvidersModule],
  controllers: [PlaybackController],
  providers: [
    PlaybackResolveService,
    MediaSignerFactory,
    {
      provide: MediaSigner,
      useFactory: (factory: MediaSignerFactory) => factory.create(),
      inject: [MediaSignerFactory],
    },
  ],
  exports: [MediaSigner],
})
export class PlaybackModule {}
