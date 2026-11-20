import { Module } from '@nestjs/common';
import { ProvidersController } from './providers.controller';
import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YoutubeMetadataAdapter } from './youtube-metadata.adapter';

@Module({
  controllers: [ProvidersController],
  providers: [ProviderRegistry, InternalCatalogAdapter, YoutubeMetadataAdapter],
  exports: [ProviderRegistry, YoutubeMetadataAdapter],
})
export class ProvidersModule {}
