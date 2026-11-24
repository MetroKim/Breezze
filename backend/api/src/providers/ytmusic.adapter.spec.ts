import { ProviderCacheService } from './provider-cache.service';
import { YtMusicAdapter } from './ytmusic.adapter';

describe('YtMusicAdapter capability contract', () => {
  const adapter = new YtMusicAdapter({} as ProviderCacheService);

  it('advertises metadata discovery without playback or download rights', () => {
    expect(adapter.capabilities).toEqual({
      search: true,
      metadata: true,
      availability: false,
      playback: false,
      download: false,
      artists: true,
      charts: true,
    });
  });

  it('keeps invalid chart countries and artist ids away from the upstream', async () => {
    await expect(adapter.getCharts('TZA')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_CHART_COUNTRY',
    });
    await expect(adapter.getArtist('../admin')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_ARTIST_ID',
    });
  });

  it('does not call upstream for one-character artist searches', async () => {
    await expect(adapter.searchArtists('a')).resolves.toMatchObject({
      kind: 'ok', value: { source: 'youtube_music', artists: [] },
    });
  });

  it('rejects invalid watch-queue IDs and limits before sending requests', async () => {
    await expect(adapter.getWatchQueue('bad-id')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_ID',
    });
    await expect(adapter.getWatchQueue('abcdefghijk', 100)).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_QUEUE_LIMIT',
    });
  });

  it('returns only non-playable metadata from the watch-queue sidecar', async () => {
    const cache = { get: jest.fn().mockResolvedValue(null), set: jest.fn().mockResolvedValue(undefined) };
    const client = new YtMusicAdapter(cache as unknown as ProviderCacheService);
    const upstream = jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({
        source: 'youtube_music',
        seedVideoId: 'abcdefghijk',
        playlistId: 'RDAMVMabcdefghijk',
        tracks: [{ providerTrackId: 'abcdefghijk', title: 'Example', artist: 'Artist' }],
        playbackAvailable: false,
      }),
    } as Response);
    try {
      const result = await client.getWatchQueue('abcdefghijk', 5);
      expect(result).toMatchObject({
        kind: 'ok',
        value: {
          source: 'youtube_music',
          seedVideoId: 'abcdefghijk',
          playbackAvailable: false,
        },
      });
      expect(upstream).toHaveBeenCalledWith(
        expect.objectContaining({ pathname: '/watch-queue/abcdefghijk' }),
        expect.objectContaining({ signal: expect.anything() }),
      );
    } finally {
      upstream.mockRestore();
    }
  });

  it('does not expose a song playback-launch method', () => {
    expect((adapter as unknown as { getPlaybackLaunch?: unknown }).getPlaybackLaunch)
      .toBeUndefined();
  });
});
