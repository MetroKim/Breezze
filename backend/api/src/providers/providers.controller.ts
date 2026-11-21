import { Controller, Get, Param, Query } from '@nestjs/common';
import { ProviderRegistry } from './provider-registry.service';

// Read-only provider discovery and official-player handoff endpoints.
@Controller('providers')
export class ProvidersController {
  constructor(private readonly registry: ProviderRegistry) {}

  @Get()
  list() {
    return this.registry.list();
  }

  @Get(':id/tracks/:trackId')
  getTrack(@Param('id') id: string, @Param('trackId') trackId: string) {
    const adapter = this.registry.get(id);
    if (!adapter) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    if (!adapter.capabilities.metadata) {
      return { kind: 'unsupported', reason: 'METADATA_NOT_CAPABLE' };
    }
    return adapter.getTrack(trackId);
  }

  /**
   * Returns a link to YouTube's own player, not a media stream.
   * The client must open the official player after a user gesture.
   */
  @Get(':id/playback/:trackId')
  getPlaybackLaunch(@Param('id') id: string, @Param('trackId') trackId: string) {
    const adapter = this.registry.get(id);
    if (!adapter) return { kind: 'unsupported', reason: 'PROVIDER_NOT_FOUND' };
    if (!adapter.getPlaybackLaunch) {
      return { kind: 'unsupported', reason: 'OFFICIAL_PLAYER_HANDOFF_NOT_SUPPORTED' };
    }
    return adapter.getPlaybackLaunch(trackId);
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
