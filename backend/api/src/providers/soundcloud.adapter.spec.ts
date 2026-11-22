import { SoundCloudAdapter } from './soundcloud.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('SoundCloudAdapter', () => {
  const cache = { get: jest.fn().mockResolvedValue(null), set: jest.fn().mockResolvedValue(undefined) };
  const originalFetch = global.fetch;
  const originalEnv = { ...process.env };
  let adapter: SoundCloudAdapter;
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.SOUNDCLOUD_CLIENT_ID = 'test-client';
    process.env.SOUNDCLOUD_ENABLED = 'true';
    adapter = new SoundCloudAdapter(cache as unknown as ProviderCacheService);
  });
  afterEach(() => { process.env = { ...originalEnv }; });
  afterAll(() => { global.fetch = originalFetch; });

  it('searches SoundCloud using its configured API client and normalizes metadata', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true, json: async () => ({ collection: [{
        id: 99, title: 'Cloud Song', duration: 182000,
        permalink_url: 'https://soundcloud.com/example/cloud-song',
        artwork_url: 'https://i1.sndcdn.com/artworks-large.jpg',
        user: { username: 'Example Artist' },
      }] }),
    }) as unknown as typeof fetch;
    const result = await adapter.search('cloud song');
    expect(result).toMatchObject({ kind: 'ok', value: [{
      providerTrackId: '99', title: 'Cloud Song', artist: 'Example Artist',
      durationSec: 182, artworkUrl: 'https://i1.sndcdn.com/artworks-t500x500.jpg',
      sourceUrl: 'https://soundcloud.com/example/cloud-song',
    }] });
    expect(global.fetch).toHaveBeenCalledWith(
      expect.objectContaining({ href: expect.stringContaining('client_id=test-client') }),
      expect.any(Object),
    );
    expect(adapter.capabilities).toMatchObject({ playback: false, availability: false });
  });

  it('fails closed when the SoundCloud developer client ID is missing', async () => {
    delete process.env.SOUNDCLOUD_CLIENT_ID;
    adapter = new SoundCloudAdapter(cache as unknown as ProviderCacheService);
    await expect(adapter.search('test')).resolves.toMatchObject({ kind: 'unsupported', reason: 'SOUNDCLOUD_NOT_CONFIGURED' });
    expect(global.fetch).not.toHaveBeenCalled();
  });
});
