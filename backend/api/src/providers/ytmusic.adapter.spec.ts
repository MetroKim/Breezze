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

  it('does not expose a song playback-launch method', () => {
    expect((adapter as unknown as { getPlaybackLaunch?: unknown }).getPlaybackLaunch)
      .toBeUndefined();
  });
});
