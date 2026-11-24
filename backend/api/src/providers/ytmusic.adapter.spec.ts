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

  it('validates album, playlist, mood and suggestion inputs without upstream access', async () => {
    await expect(adapter.getAlbum('not-an-album')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_ALBUM_ID',
    });
    await expect(adapter.getPlaylist('../private')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_PLAYLIST_ID',
    });
    await expect(adapter.getMoodPlaylists('../env')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_MOOD_PARAMS',
    });
    await expect(adapter.getSuggestions('x')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_QUERY',
    });
    await expect(adapter.getSuggestions('music', 999)).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_YTMUSIC_LIMIT',
    });
  });

  it('returns only metadata for public album and playlists', async () => {
    const cache = { get: jest.fn().mockResolvedValue(null), set: jest.fn().mockResolvedValue(undefined) };
    const client = new YtMusicAdapter(cache as unknown as ProviderCacheService);
    const upstream = jest.spyOn(global, 'fetch').mockImplementation(async (input) => {
      const url = new URL(String(input));
      if (url.pathname.startsWith('/albums/')) {
        return { ok: true, json: async () => ({
          source: 'youtube_music',
          album: { albumId: 'MPREabcdefghij', title: 'Album', tracks: [] },
          playbackAvailable: false,
        }) } as Response;
      }
      return { ok: true, json: async () => ({
        source: 'youtube_music',
        playlist: { playlistId: 'OLAK5uy_abcdefghij', title: 'Public playlist', tracks: [] },
        playbackAvailable: false,
      }) } as Response;
    });
    try {
      await expect(client.getAlbum('MPREabcdefghij')).resolves.toMatchObject({
        kind: 'ok', value: { playbackAvailable: false, album: { title: 'Album' } },
      });
      await expect(client.getPlaylist('OLAK5uy_abcdefghij')).resolves.toMatchObject({
        kind: 'ok', value: { playbackAvailable: false, playlist: { title: 'Public playlist' } },
      });
      expect(upstream).toHaveBeenCalledTimes(2);
    } finally {
      upstream.mockRestore();
    }
  });

  it('refuses catalog payloads that try to claim playback access', async () => {
    const cache = { get: jest.fn().mockResolvedValue(null), set: jest.fn() };
    const client = new YtMusicAdapter(cache as unknown as ProviderCacheService);
    const upstream = jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({
        source: 'youtube_music',
        album: { title: 'Not an authorized stream', tracks: [] },
        playbackAvailable: true,
      }),
    } as Response);
    try {
      await expect(client.getAlbum('MPREabcdefghij')).resolves.toMatchObject({
        kind: 'error', code: 'YTMUSIC_INVALID_RESPONSE',
      });
      expect(cache.set).not.toHaveBeenCalled();
    } finally {
      upstream.mockRestore();
    }
  });

  it('rejects the experimental audio endpoint unless explicitly opted in', async () => {
    const prior = process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT;
    delete process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT;
    try {
      await expect(adapter.getAudioCandidate('abcdefghijk')).resolves.toMatchObject({
        kind: 'unsupported',
      });
    } finally {
      if (prior === undefined) delete process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT;
      else process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT = prior;
    }
  });

  it('only accepts direct, unexpired googlevideo audio candidate URLs in development', async () => {
    const priorFlag = process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT;
    const priorEnv = process.env.RAILWAY_ENVIRONMENT_NAME;
    process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT = 'true';
    process.env.RAILWAY_ENVIRONMENT_NAME = 'staging';
    const cache = { get: jest.fn(), set: jest.fn() };
    const client = new YtMusicAdapter(cache as unknown as ProviderCacheService);
    const expiry = Date.now() + 600_000;
    const payload = (url: string) => ({
      source: 'youtube_music',
      providerTrackId: 'abcdefghijk',
      experimental: true,
      candidate: { streamUrl: url, mimeType: 'audio/mp4',
        bitrateKbps: 128, expiresAt: new Date(expiry).toISOString() },
    });
    const upstream = jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true, status: 200, json: async () => payload('https://evilgooglevideo.com/a'),
    } as Response);
    try {
      await expect(client.getAudioCandidate('abcdefghijk')).resolves.toMatchObject({
        kind: 'error', code: 'YTMUSIC_INVALID_AUDIO_RESPONSE',
      });
      upstream.mockResolvedValue({
        ok: true, status: 200,
        json: async () => payload('https://rr4.googlevideo.com/videoplayback?expire=9999999999'),
      } as Response);
      await expect(client.getAudioCandidate('abcdefghijk')).resolves.toMatchObject({
        kind: 'ok', value: { candidate: { mimeType: 'audio/mp4' } },
      });
    } finally {
      upstream.mockRestore();
      if (priorFlag === undefined) delete process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT;
      else process.env.BREEZZE_YTMUSIC_AUDIO_EXPERIMENT = priorFlag;
      if (priorEnv === undefined) delete process.env.RAILWAY_ENVIRONMENT_NAME;
      else process.env.RAILWAY_ENVIRONMENT_NAME = priorEnv;
    }
  });

  it('does not expose a song playback-launch method', () => {
    expect((adapter as unknown as { getPlaybackLaunch?: unknown }).getPlaybackLaunch)
      .toBeUndefined();
  });
});
