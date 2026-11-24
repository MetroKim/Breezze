import { DiscoveryService } from './discovery.service';

describe('DiscoveryService: Deezer catalog + YouTube Music video', () => {
  const originalFetch = global.fetch;
  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });
  const reply = (data: unknown, status = 200) => ({
    ok: status >= 200 && status < 300, status, json: async () => data,
  }) as unknown as Response;

  it('uses Deezer global chart without falsely claiming a country or daily ranking', async () => {
    global.fetch = jest.fn().mockResolvedValue(reply({ data: [
      { id: 42, title: 'Example', duration: 123, artist: { id: 9, name: 'Artist' },
        album: { id: 88, title: 'Record', cover_medium: 'https://images.test/a' },
        preview: 'https://cdnt-preview.dzcdn.net/api/1/clip.mp3' },
    ] }));
    const service = new DiscoveryService();
    const chart = await service.songsChart('TZ');
    const daily = await service.dailyTop100('TZ');
    expect(chart).toMatchObject({ source: 'Deezer', territory: 'GLOBAL' });
    expect(chart.items[0]).toMatchObject({
      id: '42', rank: 1, artist: 'Artist', albumId: 88,
      playback: 'preview_only',
    });
    expect(daily).toMatchObject({
      territory: 'GLOBAL', chartType: 'deezer_global_chart',
      dailyTop100Available: false,
    });
    expect((global.fetch as jest.Mock).mock.calls[0][0].toString())
      .toContain('/chart/0/tracks?limit=100');
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('requires verified release dates before showing Deezer albums as new', async () => {
    const date = (n: number) =>
      new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
    global.fetch = jest.fn().mockImplementation(async (url: URL) => {
      if (url.pathname === '/chart/0/albums') return reply({ data: [
        { id: 10 }, { id: 11 }, { id: 12 },
      ] });
      if (url.pathname === '/album/10') return reply({
        id: 10, title: 'Recent', release_date: date(4),
        artist: { name: 'Singer' },
      });
      if (url.pathname === '/album/11') return reply({
        id: 11, title: 'Old', release_date: date(90),
        artist: { name: 'Singer' },
      });
      return reply({ id: 12, title: 'Unknown date', artist: { name: 'Singer' } });
    });
    const service = new DiscoveryService();
    const releases = await service.newReleases();
    expect(releases.items.map(x => x.id)).toEqual(['10']);
    expect(releases.items[0].releaseDate).toBe(date(4));
    expect(releases.territory).toBe('GLOBAL');
    expect(global.fetch).toHaveBeenCalledTimes(4);
  });

  it('returns album tracks with Deezer preview metadata and upstream genres', async () => {
    global.fetch = jest.fn().mockResolvedValue(reply({
      id: 302127, title: 'Discovery', record_type: 'album',
      artist: { id: 27, name: 'Daft Punk' },
      genres: { data: [{ name: 'Electronic' }] },
      tracks: { data: [
        { id: 3135553, title: 'One More Time', duration: 320,
          artist: { name: 'Daft Punk' }, preview: 'https://cdnt-preview.dzcdn.net/preview.mp3',
          track_position: 1 },
      ] },
    }));
    const result = await new DiscoveryService().albumTracks('302127');
    expect(result.album).toMatchObject({
      title: 'Discovery', genres: ['Electronic'], isCompilation: false,
    });
    expect(result.items[0]).toMatchObject({
      id: '3135553', previewUrl: 'https://cdnt-preview.dzcdn.net/preview.mp3',
      durationMs: 320000, trackNumber: 1, playback: 'preview_only',
    });
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('rejects malformed Deezer IDs before network access', async () => {
    const spy = jest.fn();
    global.fetch = spy;
    const service = new DiscoveryService();
    await expect(service.albumTracks('../user')).rejects.toThrow('INVALID_DEEZER_ALBUM_ID');
    await expect(service.artistAlbums('../user')).rejects.toThrow('INVALID_DEEZER_ARTIST_ID');
    expect(spy).not.toHaveBeenCalled();
  });

  it('searches Deezer artists and tracks; never returns a non-Deezer preview host', async () => {
    global.fetch = jest.fn().mockImplementation(async (url: URL) => {
      if (url.pathname === '/search/track') return reply({ data: [{
        id: 1, title: 'Example', artist: { name: 'Artist' },
        preview: 'https://evil.example/mp3', album: { id: 9, title: 'Album' },
      }] });
      if (url.pathname === '/search/artist') return reply({ data: [{
        id: 22, name: 'Artist', link: 'https://www.deezer.com/artist/22',
      }] });
      return reply({ data: [] });
    });
    const service = new DiscoveryService();
    const songs = await service.searchTracks('example');
    expect(songs.items[0]).toMatchObject({ id: '1', previewUrl: null, playback: 'external_catalog_only' });
    const artists = await service.searchArtists('artist');
    expect(artists.items).toMatchObject([{ id: '22', name: 'Artist' }]);
  });

  it('retries transient Deezer chart 503 once and caches only success', async () => {
    global.fetch = jest.fn()
      .mockResolvedValueOnce(reply(null, 503))
      .mockResolvedValueOnce(reply({ data: [] }));
    const service = new DiscoveryService();
    await service.songsChart();
    await service.songsChart();
    expect(global.fetch).toHaveBeenCalledTimes(2);
  });

  it('never retries Deezer 400 and does not invent chart results', async () => {
    global.fetch = jest.fn().mockResolvedValue(reply({}, 400));
    await expect(new DiscoveryService().songsChart('TZ')).rejects.toThrow('DEEZER_HTTP_400');
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('keeps original YouTube Music video IDs and rejects malformed video rows', async () => {
    global.fetch = jest.fn().mockResolvedValue(reply({ videos: [
      { videoId: 'not-valid', title: 'Invalid' },
      { videoId: 'abcDEF12_-3', title: 'Official', artist: 'Artist' },
      { videoId: 'abcDEF12_-3', title: 'Duplicate' },
    ] }));
    const result = await new DiscoveryService().musicVideos('Artist');
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      id: 'abcDEF12_-3', title: 'Official', playback: 'external_youtube_only',
    });
  });
});
