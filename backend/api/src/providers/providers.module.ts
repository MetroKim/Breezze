import { Module } from '@nestjs/common';
import { ProvidersController } from './providers.controller';
import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { AudiusAdapter } from './audius.adapter';
import { JamendoAdapter } from './jamendo.adapter';
import { ProviderCacheService } from './provider-cache.service';

@Module({
  controllers: [ProvidersController],
  providers: [
    ProviderRegistry,
    InternalCatalogAdapter,
    YtMusicAdapter,
    AudiusAdapter,
    JamendoAdapter,
    ProviderCacheService,
  ],
  exports: [ProviderRegistry],
})
export class ProvidersModule {}
