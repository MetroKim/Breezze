import { PrismaService } from '../prisma.service';
import { SearchService } from './search.service';
import { ProviderRegistry } from '../providers/provider-registry.service';
import { RightsDecisionService } from '../rights/rights-decision.service';

describe('SearchService', () => {
  const tracks = [{ id: 'track-1', title: 'Amapiano Nights' }];
  const artists = [{ id: 'artist-1', name: 'Amapiano Collective', tracks: [{ id: 'track-1' }] }];
  const albums = [{ id: 'album-1', title: 'Amapiano Sessions', tracks: [{ id: 'track-1' }] }];

  const prisma = {
    track: { findMany: jest.fn() },
    artist: { findMany: jest.fn() },
    album: { findMany: jest.fn() },
  };

  const youtubeMusic = {
    providerId: 'youtube_music',
    capabilities: { search: true },
    search: jest.fn().mockResolvedValue({ kind: 'ok', value: [] }),
  };
  const providers = {
    list: jest.fn().mockReturnValue([{ providerId: 'youtube_music', capabilities: { search: true } }]),
    get: jest.fn().mockReturnValue(youtubeMusic),
  };

  const rights = { filterMetadataDisplay: jest.fn() };
  let service: SearchService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.track.findMany.mockResolvedValue(tracks);
    prisma.artist.findMany.mockResolvedValue(artists);
    prisma.album.findMany.mockResolvedValue(albums);
    rights.filterMetadataDisplay.mockResolvedValue(new Set(['track-1']));
    service = new SearchService(prisma as unknown as PrismaService, providers as unknown as ProviderRegistry, rights as unknown as RightsDecisionService);
  });

  it('returns empty result groups for queries shorter than two characters', async () => {
    await expect(service.search(' a ', 'TZ')).resolves.toEqual({
      tracks: [],
      artists: [],
      albums: [],
      externalTracks: [],
      externalProviderStatus: 'skipped',
      providerStatuses: [],
    });

    expect(prisma.track.findMany).not.toHaveBeenCalled();
    expect(prisma.artist.findMany).not.toHaveBeenCalled();
    expect(prisma.album.findMany).not.toHaveBeenCalled();
  });

  it('trims the query and searches tracks, artists and albums with bounded results', async () => {
    await expect(service.search('  Amapiano  ', 'TZ')).resolves.toEqual({
      tracks,
      artists: [{ id: 'artist-1', name: 'Amapiano Collective' }],
      albums: [{ id: 'album-1', title: 'Amapiano Sessions' }],
      externalTracks: [],
      externalProviderStatus: 'ok',
      providerStatuses: [{ providerId: 'youtube_music', status: 'ok' }],
    });

    expect(prisma.track.findMany).toHaveBeenCalledWith({
      where: { title: { contains: 'Amapiano', mode: 'insensitive' } },
      include: { artist: true, album: true },
      take: 20,
    });
    expect(prisma.artist.findMany).toHaveBeenCalledWith({
      where: { name: { contains: 'Amapiano', mode: 'insensitive' } },
      include: { tracks: { select: { id: true }, take: 100 } },
      take: 5,
    });
    expect(youtubeMusic.search).toHaveBeenCalledWith('Amapiano');
    expect(rights.filterMetadataDisplay).toHaveBeenCalledWith(['track-1'], 'TZ');
    expect(prisma.album.findMany).toHaveBeenCalledWith({
      where: { title: { contains: 'Amapiano', mode: 'insensitive' } },
      include: { tracks: { select: { id: true }, take: 100 } },
      take: 5,
    });
  });

  it('keeps local and other provider results when one provider throws', async () => {
    const other = {
      providerId: 'other',
      capabilities: { search: true },
      search: jest.fn().mockResolvedValue({ kind: 'ok', value: [{ providerTrackId: 'other-1' }] }),
    };
    providers.list.mockReturnValueOnce([
      { providerId: 'youtube_music', capabilities: { search: true } },
      { providerId: 'other', capabilities: { search: true } },
    ]);
    providers.get.mockImplementation((id: string) => id === 'other' ? other : youtubeMusic);
    youtubeMusic.search.mockRejectedValueOnce(new Error('provider unavailable'));

    const result = await service.search('Amapiano', 'TZ');

    expect(result.tracks).toEqual(tracks);
    expect(result.externalTracks).toEqual([
      expect.objectContaining({ providerTrackId: 'other-1', providerId: 'other' }),
    ]);
    expect(result.externalProviderStatus).toBe('ok');
    expect(result.providerStatuses).toEqual([
      { providerId: 'youtube_music', status: 'error', code: 'PROVIDER_SEARCH_FAILED', retryable: true },
      { providerId: 'other', status: 'ok' },
    ]);
  });
});
