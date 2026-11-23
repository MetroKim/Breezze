import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { ReplayService } from './replay.service';

describe('ReplayService', () => {
  const prisma = {
    listeningEvent: { findMany: jest.fn() },
    track: { findMany: jest.fn() },
  };
  const rights = { filterMetadataDisplay: jest.fn() };
  let service: ReplayService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.listeningEvent.findMany.mockResolvedValue([
      { trackId: 'track-1' },
      { trackId: 'track-1' },
      { trackId: 'track-2' },
    ]);
    prisma.track.findMany.mockResolvedValue([{
      id: 'track-1',
      title: 'Visible song',
      artist: { id: 'artist-1', name: 'Visible artist' },
    }]);
    rights.filterMetadataDisplay.mockResolvedValue(new Set(['track-1']));
    service = new ReplayService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
    );
  });

  it('uses only server-verified events and hides tracks unavailable in the edge territory', async () => {
    await expect(service.summary('user-1', 'TZ')).resolves.toEqual({
      totalPlays: 2,
      topSongIds: [{
        id: 'track-1',
        title: 'Visible song',
        artist: 'Visible artist',
        plays: 2,
      }],
      topArtistIds: [{ id: 'artist-1', name: 'Visible artist', plays: 2 }],
    });

    expect(prisma.listeningEvent.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', isServerVerified: true },
      select: { trackId: true },
    });
    expect(rights.filterMetadataDisplay).toHaveBeenCalledWith(
      ['track-1', 'track-2'],
      'TZ',
    );
  });

  it('returns no track metadata when trusted edge territory is unavailable', async () => {
    rights.filterMetadataDisplay.mockResolvedValue(new Set());
    await expect(service.summary('user-1', undefined)).resolves.toMatchObject({
      totalPlays: 0,
      topSongIds: [],
      topArtistIds: [],
    });
    expect(prisma.track.findMany).not.toHaveBeenCalled();
  });
});
