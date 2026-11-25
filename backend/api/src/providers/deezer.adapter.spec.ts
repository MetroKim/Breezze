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

  it('searches Deezer and normalizes metadata without claiming playback rights', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true, json: async () => ({ data: [{
        id: 42, title: 'Example Song', duration: 211, link: 'https://www.deezer.com/track/42',
        preview: 'https://cdnt-preview.dzcdn.net/api/1/clip',
        artist: { name: 'Example Artist' }, album: { cover_medium: 'https://cdn.example/cover.jpg' },
      }] }),
    }) as unknown as typeof fetch;
    const result = await adapter.search('example song');
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

  it('preserves good search results when another Deezer record is malformed', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true, json: async () => ({ data: [
        null,
        [],
        { id: 'not-a-number', title: 'Bad ID', artist: { name: 'Someone' } },
        { id: 22, title: 9, artist: { name: 'Someone' } },
        { id: 23, title: 'Bad artist', artist: { name: 99 } },
        { id: 44, title: ' Good Track ', duration: 203,
          artist: { name: ' Real Artist ' },
          album: { cover_big: 'http://unsecured.test/cover.jpg',
            cover_medium: 'https://art.example.test/safe.jpg' },
          preview: 'https://cdn.dzcdn.net.evil.test/fake.mp3',
          link: 'https://deezer.com.evil.test/track/44' },
      ] }),
    }) as unknown as typeof fetch;

    const result = await adapter.search('good track');
    expect(result.kind).toBe('ok');
    if (result.kind !== 'ok') throw new Error('Expected recovered catalog');
    expect(result.value).toHaveLength(1);
    expect(result.value[0]).toMatchObject({
      providerTrackId: '44',
      title: 'Good Track',
      artist: 'Real Artist',
      artworkUrl: 'https://art.example.test/safe.jpg',
      durationSec: 203,
    });
    expect(result.value[0].sourceUrl).toBeUndefined();
    expect(result.value[0].previewUrl).toBeUndefined();
    expect(cache.set).toHaveBeenCalledTimes(1);
  });

  it('keeps valid official preview and Deezer URLs and rejects credentials', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true, json: async () => ({ data: [
        { id: 45, title: 'Another track', artist: { name: 'Singer' },
          link: 'https://www.deezer.com/track/45',
          preview: 'https://cdnt-preview.dzcdn.net/api/1/clip',
          album: { cover_big: 'https://user:password@img.test/private.jpg',
            cover_medium: 'https://img.test/cover.jpg' } },
      ] }),
    }) as unknown as typeof fetch;
    const result = await adapter.search('another track');
    expect(result).toMatchObject({ kind: 'ok', value: [{
      sourceUrl: 'https://www.deezer.com/track/45',
      previewUrl: 'https://cdnt-preview.dzcdn.net/api/1/clip',
      artworkUrl: 'https://img.test/cover.jpg',
    }] });
  });

  it('refuses disabled-provider requests without contacting Deezer', async () => {
    process.env.DEEZER_ENABLED = 'false';
    const upstream = jest.fn();
    global.fetch = upstream as unknown as typeof fetch;
    await expect(adapter.search('test song')).resolves.toMatchObject({
      kind: 'unsupported',
    });
    await expect(adapter.getTrack('45')).resolves.toMatchObject({
      kind: 'unsupported',
    });
    expect(upstream).not.toHaveBeenCalled();
    expect(cache.get).not.toHaveBeenCalled();
  });

});
