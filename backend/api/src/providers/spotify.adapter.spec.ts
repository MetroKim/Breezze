import { SpotifyAdapter } from './spotify.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('SpotifyAdapter official metadata-only contract', () => {
  const priorId = process.env.SPOTIFY_CLIENT_ID;
  const priorSecret = process.env.SPOTIFY_CLIENT_SECRET;
  const priorEnabled = process.env.SPOTIFY_ENABLED;
  const cache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
  };
  const validId = '4iV5W9uYEdYUVa79Axb7Rh';
  let adapter: SpotifyAdapter;

  beforeEach(() => {
    process.env.SPOTIFY_CLIENT_ID = 'spotify-test-id';
    process.env.SPOTIFY_CLIENT_SECRET = 'spotify-test-secret';
    process.env.SPOTIFY_ENABLED = 'true';
    jest.clearAllMocks();
    adapter = new SpotifyAdapter(cache as unknown as ProviderCacheService);
  });

  afterEach(() => {
    jest.restoreAllMocks();
    if (priorId === undefined) delete process.env.SPOTIFY_CLIENT_ID;
    else process.env.SPOTIFY_CLIENT_ID = priorId;
    if (priorSecret === undefined) delete process.env.SPOTIFY_CLIENT_SECRET;
    else process.env.SPOTIFY_CLIENT_SECRET = priorSecret;
    if (priorEnabled === undefined) delete process.env.SPOTIFY_ENABLED;
    else process.env.SPOTIFY_ENABLED = priorEnabled;
  });

  function respond() {
    const fetchMock = jest.spyOn(global, 'fetch').mockImplementation(async input => {
      const url = new URL(String(input));
      if (url.hostname === 'accounts.spotify.com') {
        return {
          ok: true, json: async () =>
            ({ access_token: 'test-bearer-spotify', token_type: 'Bearer', expires_in: 3600 }),
        } as Response;
      }
      return { ok: true, status: 200, json: async () => ({
        tracks: { items: [
          { id: validId, name: 'Original Song',
            artists: [{ name: 'Artist' }],
            duration_ms: 243000,
            album: { images: [{ url: 'https://i.scdn.co/image/cover' }] } },
          { id: validId, name: 'duplicate', artists: [{ name: 'Other' }] },
          { id: 'invalid', name: 'invalid', artists: [{ name: 'Other' }] },
        ] },
      }) } as Response;
    });
    return fetchMock;
  }

  it('disables Spotify when credentials are missing; no upstream requests', async () => {
    delete process.env.SPOTIFY_CLIENT_SECRET;
    const upstream = jest.spyOn(global, 'fetch');
    expect(adapter.enabled).toBe(false);
    await expect(adapter.search('music')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'SPOTIFY_NOT_CONFIGURED',
    });
    expect(upstream).not.toHaveBeenCalled();
  });

  it('supports real Spotify discovery but never emits native media URLs', async () => {
    const upstream = respond();
    const result = await adapter.search('afrobeat');
    expect(result).toMatchObject({ kind: 'ok', value: [{
      providerTrackId: validId,
      title: 'Original Song', artist: 'Artist',
      durationSec: 243,
      artworkUrl: 'https://i.scdn.co/image/cover',
      sourceUrl: 'https://open.spotify.com/track/' + validId,
    }] });
    expect(result.kind === 'ok' && result.value).toHaveLength(1);
    expect(JSON.stringify(result)).not.toContain('spotify-test-secret');
    expect(JSON.stringify(result)).not.toContain('test-bearer-spotify');
    expect(JSON.stringify(result)).not.toContain('streamUrl');
    const search = upstream.mock.calls.find(([input]) => String(input).includes('api.spotify.com'));
    expect(search).toBeDefined();
    const url = new URL(String(search![0]));
    expect(url.searchParams.get('type')).toBe('track');
    expect(url.searchParams.get('limit')).toBe('10'); // 2026 dev-mode ceiling
    expect(search![1]).toMatchObject({
      headers: { Authorization: 'Bearer test-bearer-spotify' },
    });
    expect(cache.set).toHaveBeenCalledWith(
      expect.stringContaining('provider:spotify:search:v1:'), expect.anything(), 90,
    );
  });

  it('validates Spotify IDs and does not send bogus track lookup requests', async () => {
    const upstream = jest.spyOn(global, 'fetch');
    await expect(adapter.getTrack('bad')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_SPOTIFY_TRACK_ID',
    });
    expect(upstream).not.toHaveBeenCalled();
  });

  it('keeps provider sessions separate from Breezze native and offline grants', async () => {
    expect(adapter.capabilities).toMatchObject({
      playback: false, availability: false, download: false,
    });
    await expect(adapter.getAvailability()).resolves.toMatchObject({ kind: 'unsupported' });
    await expect(adapter.resolvePlayback({
      providerTrackId: validId, territory: 'TZ',
      authorization: { action: 'stream.full', attribution: null, expiresAt: null },
    })).resolves.toMatchObject({ kind: 'unsupported' });
  });

  it('converts 429 into an explicit retryable quota failure without leaking credentials', async () => {
    jest.spyOn(global, 'fetch').mockImplementation(async input => {
      const url = new URL(String(input));
      return url.hostname === 'accounts.spotify.com'
        ? { ok: true, json: async () => ({
            access_token: 'secret-token', token_type: 'Bearer', expires_in: 3600,
          }) } as Response
        : { ok: false, status: 429,
            json: async () => ({ error: 'secret-token' }) } as Response;
    });
    const result = await adapter.search('music');
    expect(result).toMatchObject({
      kind: 'error', code: 'SPOTIFY_RATE_LIMITED', retryable: true,
    });
    expect(JSON.stringify(result)).not.toContain('secret-token');
  });
});
