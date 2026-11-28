import { Module } from '@nestjs/common';
import { ProvidersController } from './providers.controller';
import { ProviderRegistry } from './provider-registry.service';
import { InternalCatalogAdapter } from './internal-catalog.adapter';
import { YtMusicAdapter } from './ytmusic.adapter';
import { DeezerAdapter } from './deezer.adapter';
import { SpotifyAdapter } from './spotify.adapter';
import { MusicBrainzAdapter } from './musicbrainz.adapter';
import { ProviderCacheService } from './provider-cache.service';
import { OfficialYouTubeDataService } from './official-youtube-data.service';
import { ArtistCatalogService } from './artist-catalog.service';
import { RightsModule } from '../rights/rights.module';
import { OpenSubsonicAdapter } from './opensubsonic.adapter';
import { OpenSubsonicAudioController } from './opensubsonic-audio.controller';
import { AuthorizedAudioCatalogController } from './authorized-audio-catalog.controller';
import { CommonsOpenMediaService } from './commons-open-media.service';
import { CommonsOpenMediaController } from './commons-open-media.controller';

@Module({
  imports: [RightsModule],
  controllers: [ProvidersController, OpenSubsonicAudioController, AuthorizedAudioCatalogController, CommonsOpenMediaController],
  providers: [
    ProviderRegistry,
    ArtistCatalogService,
    InternalCatalogAdapter,
    OpenSubsonicAdapter,
    CommonsOpenMediaService,
    YtMusicAdapter,
    DeezerAdapter,
    SpotifyAdapter,
    MusicBrainzAdapter,
    ProviderCacheService,
    OfficialYouTubeDataService,
  ],
  exports: [ProviderRegistry],
})
export class ProvidersModule {}
