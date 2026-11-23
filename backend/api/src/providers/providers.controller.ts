import { Controller, Get, Param, Query } from '@nestjs/common';
import { ProviderRegistry } from './provider-registry.service';

// Read-only provider discovery and metadata endpoints.
@Controller('providers')
export class ProvidersController {
  constructor(private readonly registry: ProviderRegistry) {}

  @Get()
  list() {
    return this.registry.list();
  }

  @Get('search')
  searchAll(@Query('q') q: string) {
    return this.registry.searchAll(q ?? '');
  }

  @Get(':id/tracks/:trackId')
  getTrack(@Param('id') id: string, @Param('trackId') trackId: string) {
    if (id === 'breezze_internal') return { kind: 'unsupported', reason: 'USE_RIGHTS_AWARE_CATALOG_ENDPOINT' };
    const adapter = this.registry.get(id);
    if (!adapter) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    if (!adapter.capabilities.metadata) {
      return { kind: 'unsupported', reason: 'METADATA_NOT_CAPABLE' };
    }
    return adapter.getTrack(trackId);
  }

  @Get(':id/search')
  search(@Param('id') id: string, @Query('q') q: string) {
    const adapter = this.registry.get(id);
    if (!adapter) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    if (!adapter.capabilities.search) {
      return { kind: 'unsupported', reason: 'SEARCH_NOT_CAPABLE' };
    }
    return adapter.search(q ?? '');
  }
}
