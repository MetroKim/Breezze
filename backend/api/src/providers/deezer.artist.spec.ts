import { DeezerAdapter } from './deezer.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('Deezer artist supplement: strict identity and source isolation', () => {
  const savedFetch = global.fetch;
  const priorEnabled = process.env.DEEZER_ENABLED;
  const cache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
  };
  const urls: string[] = [];
  let searchArtists: Array<{ id: number; name: string }>;
  let failRelated: boolean;

  beforeEach(() => {
    process.env.DEEZER_ENABLED = 'true';
    jest.clearAllMocks();
    urls.length = 0;
    searchArtists = [{ id: 27, name: 'Singer Example' }];
    failRelated = false;
    global.fetch = jest.fn().mockImplementation(async (url: URL) => {
      const request = new URL(String(url));
      urls.push(request.pathname + request.search);
      if (request.pathname === '/search/artist') {
        return { ok: true, json: async () => ({ data: searchArtists }) };
      }
      if (request.pathname === '/artist/27/top') {
        return { ok: true, json: async () => ({ data: [
          { id: 11, title: 'Song', duration: 212,
            artist: { name: 'Singer Example' },
            album: { cover_medium: 'https://cdn.example/image.jpg' } },
          { id: 12, title: 'Wrong person', artist: { name: 'Another Singer' } },
        ] }) };
      }
      if (request.pathname === '/artist/27/albums') {
        return { ok: true, json: async () => ({ data: [
          { id: 101, title: 'The Record', release_date: '2026-10-12',
            record_type: 'album', artist: { id: 27, name: 'Singer Example' } },
          { id: 102, title: 'Unrelated', artist: { id: 999, name: 'Other' } },
        ] }) };
      }
      if (request.pathname === '/artist/27/related') {
        return failRelated
          ? { ok: false, status: 503 }
          : { ok: true, json: async () => ({ data: [
              { id: 55, name: 'Nearby Artist' },
              { id: 27, name: 'Singer Example' },
            ] }) };
      }
      return { ok: false, status: 404 };
    }) as typeof fetch;
  });
  afterAll(() => {
    global.fetch = savedFetch;
    if (priorEnabled === undefined) delete process.env.DEEZER_ENABLED;
    else process.env.DEEZER_ENABLED = priorEnabled;
  });

  const adapter = () =>
    new DeezerAdapter(cache as unknown as ProviderCacheService);

  it('accepts exactly one artist ID and filters unrelated songs and albums', async () => {
    const result = await adapter().getArtistSupplement('singer   example');
    expect(result).toMatchObject({ kind: 'ok', value: {
      matchedArtistId: '27',
      songs: [{ providerId: 'deezer', providerTrackId: '11' }],
      albums: [{ providerId: 'deezer', id: '101' }],
      relatedArtists: [{ id: '55', name: 'Nearby Artist' }],
      relatedStatus: 'ok',
    }});
    if (result.kind === 'ok') {
      expect(result.value.songs).toHaveLength(1);
      expect(result.value.albums).toHaveLength(1);
      expect(result.value.relatedArtists).toHaveLength(1);
    }
    expect(JSON.stringify(result)).not.toContain('streamUrl');
    expect(JSON.stringify(result)).not.toContain('downloadUrl');
    expect(urls.some(path => path.startsWith('/search/artist'))).toBe(true);
  });

  it('fails closed for two different artists with identical display names', async () => {
    searchArtists = [
      { id: 27, name: 'Singer Example' },
      { id: 900, name: 'Singer Example' },
    ];
    const result = await adapter().getArtistSupplement('Singer Example');
    expect(result).toMatchObject({
      kind: 'unsupported', reason: 'DEEZER_ARTIST_AMBIGUOUS',
    });
    expect(urls).toHaveLength(1);
  });

  it('keeps songs when Deezer related artists endpoint is unavailable', async () => {
    failRelated = true;
    const result = await adapter().getArtistSupplement('Singer Example');
    expect(result).toMatchObject({ kind: 'ok', value: {
      songs: [{ providerTrackId: '11' }],
      relatedStatus: 'unavailable',
      relatedArtists: [],
    }});
  });

  it('rejects empty and overlong artist names before network calls', async () => {
    await expect(adapter().getArtistSupplement('X')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'INVALID_ARTIST_QUERY',
    });
    expect(urls).toHaveLength(0);
  });
});
