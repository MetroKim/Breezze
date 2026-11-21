import { AudiusAdapter } from './audius.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('AudiusAdapter', () => {
  const cache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
  };

  let adapter: AudiusAdapter;
  const originalFetch = global.fetch;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.AUDIUS_API_URL = 'https://api.audius.co/v1';
    delete process.env.AUDIUS_API_KEY;
    adapter = new AudiusAdapter(cache as unknown as ProviderCacheService);
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  it('searches the official Audius API and normalizes track metadata', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: [{
          id: 'track123',
          title: 'Test Track',
          duration: 187,
          user: { name: 'Test Artist' },
          artwork: { '480x480': 'https://cdn.example/art.jpg' },
        }],
      }),
    }) as unknown as typeof fetch;

    const result = await adapter.search('test track');
    expect(result.kind).toBe('ok');
    if (result.kind !== 'ok') return;
    expect(result.value).toEqual([{
      providerTrackId: 'track123',
      title: 'Test Track',
      artist: 'Test Artist',
      artworkUrl: 'https://cdn.example/art.jpg',
      durationSec: 187,
    }]);
    expect(global.fetch).toHaveBeenCalledWith(
      expect.objectContaining({
        href: 'https://api.audius.co/v1/tracks/search?query=test+track&limit=20',
      }),
      expect.any(Object),
    );
  });

  it('resolves public tracks through the official stream endpoint', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: { id: 'track123', is_stream_gated: false },
      }),
    }) as unknown as typeof fetch;

    const result = await adapter.resolvePlayback({
      canonicalTrackId: '',
      providerTrackId: 'track123',
      territory: 'TZ',
      authorization: {
        action: 'stream.full',
        expiresAt: null,
        attribution: null,
      },
    });

    expect(result.kind).toBe('ok');
    if (result.kind !== 'ok') return;
    expect(result.value.url).toBe(
      'https://api.audius.co/v1/tracks/track123/stream',
    );
  });

  it('refuses gated tracks instead of attempting to bypass creator access rules', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: { id: 'track123', is_stream_gated: true },
      }),
    }) as unknown as typeof fetch;

    const result = await adapter.resolvePlayback({
      canonicalTrackId: '',
      providerTrackId: 'track123',
      territory: 'TZ',
      authorization: {
        action: 'stream.full',
        expiresAt: null,
        attribution: null,
      },
    });

    expect(result).toMatchObject({
      kind: 'unsupported',
      reason: 'AUDIUS_TRACK_GATED',
    });
  });

  it('refuses tracks restricted to a different API key', async () => {
    process.env.AUDIUS_API_KEY = 'breezze-key';
    adapter = new AudiusAdapter(cache as unknown as ProviderCacheService);
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: {
          id: 'track123',
          is_stream_gated: false,
          allowed_api_keys: ['another-app-key'],
        },
      }),
    }) as unknown as typeof fetch;

    const result = await adapter.resolvePlayback({
      canonicalTrackId: '',
      providerTrackId: 'track123',
      territory: 'TZ',
      authorization: {
        action: 'stream.full',
        expiresAt: null,
        attribution: null,
      },
    });

    expect(result.kind).toBe('unsupported');
  });
});
