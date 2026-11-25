import { MusicBrainzAdapter } from './musicbrainz.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('MusicBrainzAdapter — credential-free catalog backup', () => {
  const previous = process.env.MUSICBRAINZ_NONCOMMERCIAL_ACK;
  const previousEnabled = process.env.MUSICBRAINZ_ENABLED;
  const realFetch = global.fetch;
  const cache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
    reserveProviderInterval: jest.fn().mockResolvedValue(true),
  };
  const id = '26c1620c-fd33-4414-a202-6aabbe2303be';

  beforeEach(() => {
    jest.clearAllMocks();
    cache.get.mockResolvedValue(null);
    cache.reserveProviderInterval.mockResolvedValue(true);
    process.env.MUSICBRAINZ_NONCOMMERCIAL_ACK = 'true';
    process.env.MUSICBRAINZ_ENABLED = 'true';
  });
  afterEach(() => {
    global.fetch = realFetch;
    if (previous === undefined) delete process.env.MUSICBRAINZ_NONCOMMERCIAL_ACK;
    else process.env.MUSICBRAINZ_NONCOMMERCIAL_ACK = previous;
    if (previousEnabled === undefined) delete process.env.MUSICBRAINZ_ENABLED;
    else process.env.MUSICBRAINZ_ENABLED = previousEnabled;
  });

  const adapter = () => new MusicBrainzAdapter(cache as unknown as ProviderCacheService);

  it('fails closed without explicit noncommercial-use acknowledgment', async () => {
    delete process.env.MUSICBRAINZ_NONCOMMERCIAL_ACK;
    const upstream = jest.fn();
    global.fetch = upstream;
    await expect(adapter().search('Afrobeats')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'MUSICBRAINZ_NOT_ENABLED',
    });
    expect(upstream).not.toHaveBeenCalled();
  });

  it('searches recording metadata without a key and never invents audio URLs', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        recordings: [{
          id, title: 'Demo Song', length: 190000,
          'artist-credit': [{ name: 'Demo Artist' }, ' feat. ', { name: 'Guest' }],
        }, { id: 'not-a-uuid', title: 'Invalid', 'artist-credit': [{ name: 'Fake' }] }],
      }),
    }) as unknown as typeof fetch;
    const result = await adapter().search('Demo Song');
    expect(result).toMatchObject({
      kind: 'ok',
      value: [{
        providerTrackId: id, title: 'Demo Song',
        artist: 'Demo Artist', durationSec: 190,
        sourceUrl: 'https://musicbrainz.org/recording/' + id,
      }],
    });
    if (result.kind === 'ok') {
      expect(result.value).toHaveLength(1);
      expect(result.value[0]).not.toHaveProperty('previewUrl');
      expect(result.value[0]).not.toHaveProperty('streamUrl');
    }
    expect(cache.reserveProviderInterval).toHaveBeenCalledWith(
      'musicbrainz:recording', 1250,
    );
    expect(cache.set).toHaveBeenCalledWith(expect.stringContaining(
      'provider:musicbrainz:search:v1:'), expect.anything(), 3600,
    );
    const input = (global.fetch as jest.Mock).mock.calls[0][0];
    const options = (global.fetch as jest.Mock).mock.calls[0][1];
    const url = new URL(String(input));
    expect(url.origin).toBe('https://musicbrainz.org');
    expect(url.searchParams.get('fmt')).toBe('json');
    expect(url.searchParams.get('limit')).toBe('10');
    expect(options.headers['User-Agent']).toContain('Breezze/');
  });

  it('never bypasses the global 1/sec upstream request gate', async () => {
    cache.reserveProviderInterval.mockResolvedValue(false);
    const upstream = jest.fn();
    global.fetch = upstream;
    await expect(adapter().search('Demo Song')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'MUSICBRAINZ_RATE_BUDGET_BUSY',
    });
    expect(upstream).not.toHaveBeenCalled();
  });

  it('rejects forged recording identifiers without an upstream lookup', async () => {
    const upstream = jest.fn();
    global.fetch = upstream;
    await expect(adapter().getTrack('../secrets')).resolves.toMatchObject({
      kind: 'error', code: 'INVALID_MUSICBRAINZ_ID',
    });
    expect(upstream).not.toHaveBeenCalled();
  });

  it('does not grant native full audio or offline access', async () => {
    expect(adapter().capabilities).toMatchObject({
      playback: false, download: false, availability: false,
    });
    await expect(adapter().resolvePlayback({
      providerTrackId: id,
      territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    })).resolves.toMatchObject({ kind: 'unsupported' });
  });
});
