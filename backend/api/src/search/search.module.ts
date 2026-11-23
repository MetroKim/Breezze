import { Module } from '@nestjs/common';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';
import { ProvidersModule } from '../providers/providers.module';
import { RightsModule } from '../rights/rights.module';

@Module({
  imports: [ProvidersModule, RightsModule],
  controllers: [SearchController],
  providers: [SearchService],
})
export class SearchModule {}
