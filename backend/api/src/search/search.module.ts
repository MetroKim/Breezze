import { Module } from '@nestjs/common';
import { ProvidersModule } from '../providers/providers.module';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';

// SearchService injects the keyless YoutubeMetadataAdapter, exported
// by ProvidersModule — import it so Nest DI resolves the dependency.
@Module({
  imports: [ProvidersModule],
  controllers: [SearchController],
  providers: [SearchService],
})
export class SearchModule {}
