import { ProviderCacheService } from './provider-cache.service';
import { YtMusicAdapter } from './ytmusic.adapter';

describe('YtMusicAdapter official player handoff', () => {
  const adapter = new YtMusicAdapter({} as ProviderCacheService);

  it('returns only official YouTube player URLs for a valid video ID', () => {
    const result = adapter.getPlaybackLaunch('abcdefgh_12');
    expect(result.kind).toBe('ok');
    if (result.kind !== 'ok') return;

    expect(result.value.mode).toBe('external_official_player');
    expect(result.value.watchUrl).toBe('https://www.youtube.com/watch?v=abcdefgh_12');
    expect(result.value.embedUrl).toBe(
      'https://www.youtube-nocookie.com/embed/abcdefgh_12?playsinline=1&rel=0',
    );
    expect(result.value.supportsBackgroundAudio).toBe(false);
    expect(result.value.supportsNativeQueueControls).toBe(false);
    expect(result.value).not.toHaveProperty('streamUrl');
  });

  it('rejects malformed provider IDs', () => {
    const result = adapter.getPlaybackLaunch('not a video id');
    expect(result.kind).toBe('error');
    if (result.kind === 'error') {
      expect(result.code).toBe('INVALID_YTMUSIC_ID');
      expect(result.retryable).toBe(false);
    }
  });
});
