import { Controller, Get, Headers, Query } from '@nestjs/common';
import { SearchService } from './search.service';

@Controller('search')
export class SearchController {
  constructor(private readonly searchService: SearchService) {}

  @Get()
  search(
    @Query('q') q: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
  ) {
    return this.searchService.search(q ?? '', edgeCountry);
  }
}
