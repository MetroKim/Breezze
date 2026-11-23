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
    });
  });

  it('does not expose a song playback-launch method', () => {
    expect((adapter as unknown as { getPlaybackLaunch?: unknown }).getPlaybackLaunch)
      .toBeUndefined();
  });
});
