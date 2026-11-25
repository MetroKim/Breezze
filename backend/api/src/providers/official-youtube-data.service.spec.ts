import { OfficialYouTubeDataService } from './official-youtube-data.service';
import { ProviderCacheService } from './provider-cache.service';
import { YtMusicAdapter } from './ytmusic.adapter';

describe('Official YouTube Data API metadata and transparent video fallback', () => {
  const prior = process.env.YOUTUBE_DATA_API_KEY;
  const key = 'ci-only-youtube-metadata-test-key';
  const service = new OfficialYouTubeDataService();

  beforeEach(() => {
    process.env.YOUTUBE_DATA_API_KEY = key;
  });
  afterEach(() => {
    jest.restoreAllMocks();
    if (prior === undefined) delete process.env.YOUTUBE_DATA_API_KEY;
    else process.env.YOUTUBE_DATA_API_KEY = prior;
  });

  it('requires a server-only key; never performs a request if missing', async () => {
    delete process.env.YOUTUBE_DATA_API_KEY;
    const fetchMock = jest.spyOn(global, 'fetch');
    await expect(service.searchMusicVideos('soul music')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'YOUTUBE_DATA_KEY_NOT_CONFIGURED',
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('does not activate a staged or unrotated key in production by accident', async () => {
    const oldEnv = process.env.NODE_ENV;
    const oldEnabled = process.env.YOUTUBE_DATA_API_ENABLED;
    try {
      process.env.NODE_ENV = 'production';
      delete process.env.YOUTUBE_DATA_API_ENABLED;
      expect(service.configured).toBe(false);
      await expect(service.searchMusicVideos('public music')).resolves.toMatchObject({
        kind: 'unsupported', reason: 'YOUTUBE_DATA_KEY_NOT_CONFIGURED',
      });
      process.env.YOUTUBE_DATA_API_ENABLED = 'true';
      expect(service.configured).toBe(true);
    } finally {
      if (oldEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = oldEnv;
      if (oldEnabled === undefined) delete process.env.YOUTUBE_DATA_API_ENABLED;
      else process.env.YOUTUBE_DATA_API_ENABLED = oldEnabled;
    }
  });

  it('rejects invalid queries and limit before quota-consuming network access', async () => {
    const fetchMock = jest.spyOn(global, 'fetch');
    await expect(service.searchMusicVideos('x')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YOUTUBE_VIDEO_SEARCH',
    });
    await expect(service.searchMusicVideos('music', 999)).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YOUTUBE_VIDEO_SEARCH',
    });
    await expect(service.getVideo('../meta')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YOUTUBE_VIDEO_ID',
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('searches embeddable syndicated official music videos without supplying audio URLs', async () => {
    const upstream = jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({
        items: [
          { id: { videoId: 'abcdefghijk' },
            snippet: { title: 'Sample song', channelTitle: 'Example artist',
              liveBroadcastContent: 'none',
              thumbnails: { high: { url: 'https://i.ytimg.com/example.jpg' } } } },
          { id: { videoId: 'abcdefghijk' },
            snippet: { title: 'Duplicate', channelTitle: 'Other' } },
          { id: { videoId: 'bad_id' },
            snippet: { title: 'Invalid ID', channelTitle: 'Other' } },
        ],
      }),
    } as Response);
    const result = await service.searchMusicVideos('test song', 5);
    expect(result).toMatchObject({
      kind: 'ok', value: [{
        providerTrackId: 'abcdefghijk',
        title: 'Sample song', artist: 'Example artist',
        sourceUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
      }],
    });
    if (result.kind === 'ok') {
      expect(result.value[0]).not.toHaveProperty('streamUrl');
      expect(result.value[0]).not.toHaveProperty('previewUrl');
      expect(JSON.stringify(result)).not.toContain(key);
    }
    const url = upstream.mock.calls[0][0] as URL;
    expect(url.hostname).toBe('www.googleapis.com');
    expect(url.pathname).toBe('/youtube/v3/search');
    expect(url.searchParams.get('videoCategoryId')).toBe('10');
    expect(url.searchParams.get('videoEmbeddable')).toBe('true');
    expect(url.searchParams.get('videoSyndicated')).toBe('true');
    expect(url.searchParams.get('maxResults')).toBe('5');
  });

  it('exposes embeddability metadata, not playable audio permissions', async () => {
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true, json: async () => ({ items: [{
        id: 'abcdefghijk',
        snippet: { title: 'Public track video', channelTitle: 'Artist' },
        status: { privacyStatus: 'public', embeddable: true },
      }] }),
    } as Response);
    await expect(service.getVideo('abcdefghijk')).resolves.toMatchObject({
      kind: 'ok', value: {
        embeddable: true, playbackAvailable: false,
        watchUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
      },
    });
  });

  it('never surfaces Google error text or an environment credential', async () => {
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: false, status: 403,
      json: async () => ({ error: { message: 'key=' + key } }),
    } as Response);
    const result = await service.searchMusicVideos('song');
    expect(result).toMatchObject({ kind: 'error', code: 'YOUTUBE_DATA_UPSTREAM_REJECTED' });
    expect(JSON.stringify(result)).not.toContain(key);
  });

  it('uses official public video metadata if the ytmusicapi sidecar fails', async () => {
    const cache = { get: jest.fn().mockResolvedValue(null), set: jest.fn().mockResolvedValue(undefined) };
    const client = new YtMusicAdapter(cache as unknown as ProviderCacheService, service);
    const upstream = jest.spyOn(global, 'fetch').mockImplementation(async input => {
      const url = new URL(String(input));
      if (url.hostname === 'www.googleapis.com') {
        return { ok: true, json: async () => ({
          items: [{ id: { videoId: 'abcdefghijk' },
            snippet: { title: 'Music video', channelTitle: 'Artist' } }],
        }) } as Response;
      }
      return { ok: false, status: 503 } as Response;
    });
    const result = await client.search('music video');
    expect(result).toMatchObject({
      kind: 'ok', value: [{
        providerTrackId: 'abcdefghijk',
        sourceUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
      }],
    });
    expect(upstream).toHaveBeenCalledTimes(2);
    expect(cache.set).not.toHaveBeenCalled(); // A sidecar outage is not cached forever.
  });
});
