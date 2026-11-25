import { Module } from '@nestjs/common';
import { ProvidersController } from './providers.controller';
import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { DeezerAdapter } from './deezer.adapter';
import { SpotifyAdapter } from './spotify.adapter';
import { ProviderCacheService } from './provider-cache.service';
import { OfficialYouTubeDataService } from './official-youtube-data.service';

@Module({
  controllers: [ProvidersController],
  providers: [
    ProviderRegistry,
    InternalCatalogAdapter,
    YtMusicAdapter,
    DeezerAdapter,
    SpotifyAdapter,
    ProviderCacheService,
    OfficialYouTubeDataService,
  ],
  exports: [ProviderRegistry],
})
export class ProvidersModule {}
