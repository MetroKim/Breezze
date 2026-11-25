import { DeezerAdapter } from './deezer.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('DeezerAdapter', () => {
  const cache = { get: jest.fn().mockResolvedValue(null), set: jest.fn().mockResolvedValue(undefined) };
  const originalFetch = global.fetch;
  const originalEnabled = process.env.DEEZER_ENABLED;
  let adapter: DeezerAdapter;
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.DEEZER_ENABLED = 'true';
    adapter = new DeezerAdapter(cache as unknown as ProviderCacheService);
  });
  afterAll(() => {
    global.fetch = originalFetch;
    if (originalEnabled === undefined) delete process.env.DEEZER_ENABLED;
    else process.env.DEEZER_ENABLED = originalEnabled;
  });

  it('promotes matching songs over unrelated chart rows in public search results', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: [
          { id: 1, title: 'Unrelated', artist: { name: 'Other' } },
          { id: 2, title: 'Popular Track', artist: { name: 'Burna Boy' } },
        ],
      }),
    }) as unknown as typeof fetch;
    const result = await adapter.search('Burna Boy');
    expect(result).toMatchObject({
      kind: 'ok',
      value: [
        { providerTrackId: '2', artist: 'Burna Boy' },
        { providerTrackId: '1', title: 'Unrelated' },
      ],
    });
  });

  it('searches Deezer and normalizes metadata without claiming playback rights', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true, json: async () => ({ data: [{
        id: 42, title: 'Example Song', duration: 211, link: 'https://www.deezer.com/track/42',
        preview: 'https://cdnt-preview.dzcdn.net/api/1/clip',
        artist: { name: 'Example Artist' }, album: { cover_medium: 'https://cdn.example/cover.jpg' },
      }] }),
    }) as unknown as typeof fetch;
    const result = await adapter.search('example song');
    const searchUrl = new URL(String((global.fetch as jest.Mock).mock.calls[0][0]));
    expect(searchUrl.searchParams.get('limit')).toBe('50');
    expect(searchUrl.searchParams.get('q')).toBe('example song');
    expect(result).toMatchObject({ kind: 'ok', value: [{
      providerTrackId: '42', title: 'Example Song', artist: 'Example Artist',
      durationSec: 211, artworkUrl: 'https://cdn.example/cover.jpg',
      sourceUrl: 'https://www.deezer.com/track/42', previewUrl: 'https://cdnt-preview.dzcdn.net/api/1/clip',
    }] });
    expect(adapter.capabilities).toMatchObject({ playback: false, availability: false });
    await expect(adapter.resolvePlayback({
      providerTrackId: '42', territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    })).resolves.toMatchObject({ kind: 'unsupported' });
  });
});
