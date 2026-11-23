import { DiscoveryService } from './discovery.service';

describe('DiscoveryService album metadata', () => {
  const service = new DiscoveryService();
  let originalFetch: typeof fetch;

  beforeEach(() => {
    originalFetch = global.fetch;
  });

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it('returns only recently released chart entries in release-date order', async () => {
    const day = 86400000;
    const date = (days: number) => new Date(Date.now() - days * day).toISOString().slice(0, 10);
    global.fetch = jest.fn().mockResolvedValue({ ok: true, json: async () => ({
      feed: { results: [10, 60, -10, 2].map(n => ({ id: String(n), releaseDate: date(n) })) },
    }) });
    const result = await service.recentChartReleases('songs', 'TZ');
    expect(result.items.map(i => i.id)).toEqual(['2', '10']);
    expect(result.items.every(i => i.rank === null)).toBe(true);
    expect(result.sourceUrl).toContain('/tz/music/most-played/100/songs.json');
  });

  it('preserves only upstream-provided genre and compilation attributes', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: jest.fn().mockResolvedValue({
        results: [
          {
            wrapperType: 'collection',
            collectionId: 123,
            collectionName: 'Collection A',
            artistName: 'Artist',
            primaryGenreName: 'Electronic',
            isCompilation: true,
          },
          {
            wrapperType: 'track',
            trackId: 5,
            trackName: 'Example',
            artistName: 'Artist',
          },
        ],
      }),
    } as unknown as Response);
    const result = await service.albumTracks('123');
    expect(result.album).toMatchObject({
      id: 123,
      title: 'Collection A',
      genres: ['Electronic'],
      isCompilation: true,
    });
    expect(result.items).toHaveLength(1);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('does not infer unknown album categories', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: jest.fn().mockResolvedValue({
        results: [
          {
            wrapperType: 'collection',
            collectionId: 456,
            collectionName: 'Greatest Hits',
            artistName: 'Various Artists',
          },
        ],
      }),
    } as unknown as Response);
    const result = await service.albumTracks('456');
    expect(result.album).toMatchObject({
      genres: [],
      isCompilation: false,
    });
  });

  it('rejects invalid album IDs before network requests', async () => {
    const spy = jest.fn();
    global.fetch = spy;
    await expect(service.albumTracks('../user')).rejects.toThrow(
      'INVALID_APPLE_ALBUM_ID',
    );
    expect(spy).not.toHaveBeenCalled();
  });
});
