import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SearchService } from './search.service';

@Controller('search')
export class SearchController {
  constructor(private readonly search: SearchService) {}

  @Get()
  search(@Query('q') q: string) {
    return this.search.search(q ?? '');
  }

  @Get('external')
  @UseGuards(JwtAuthGuard)
  external(@Query('q') q: string) {
    return this.search.searchExternal(q ?? '');
  }
}
