import { JamendoAdapter } from './jamendo.adapter';
import { ProviderCacheService } from './provider-cache.service';

describe('JamendoAdapter', () => {
  const cache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
  };
  let adapter: JamendoAdapter;
  const originalFetch = global.fetch;
  const originalEnv = { ...process.env };

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.JAMENDO_CLIENT_ID = 'test-client-id';
    process.env.JAMENDO_API_TERMS_ACCEPTED = 'true';
    process.env.JAMENDO_BREEZZE_APPROVED = 'true';
    process.env.JAMENDO_ENABLED = 'true';
    delete process.env.BREEZZE_NONCOMMERCIAL;
    adapter = new JamendoAdapter(cache as unknown as ProviderCacheService);
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  it('searches Jamendo and maps actual catalogue results', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ headers: { status: 'success', code: 0 }, results: [{
        id: '12345', name: 'Open Road', artist_name: 'Test Artist',
        duration: '201', album_image: 'https://usercontent.jamendo.com/cover.jpg',
      }] }),
    }) as unknown as typeof fetch;

    const result = await adapter.search('open road');
    expect(result.kind).toBe('ok');
    if (result.kind !== 'ok') return;
    expect(result.value[0]).toMatchObject({
      providerTrackId: '12345', title: 'Open Road', artist: 'Test Artist',
      durationSec: 201, artworkUrl: 'https://usercontent.jamendo.com/cover.jpg',
      sourceUrl: 'https://www.jamendo.com/track/12345',
    });
    expect(global.fetch).toHaveBeenCalledWith(
      expect.objectContaining({ href: expect.stringContaining('/tracks/?client_id=test-client-id') }),
      expect.any(Object),
    );
  });

  it('does not enable Jamendo without explicit approval for Breezze distribution', async () => {
    delete process.env.JAMENDO_BREEZZE_APPROVED;
    adapter = new JamendoAdapter(cache as unknown as ProviderCacheService);
    await expect(adapter.search('test')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'JAMENDO_NOT_CONFIGURED',
    });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('does not call Jamendo when developer credentials and terms acceptance are missing', async () => {
    delete process.env.JAMENDO_CLIENT_ID;
    adapter = new JamendoAdapter(cache as unknown as ProviderCacheService);
    await expect(adapter.search('test')).resolves.toMatchObject({
      kind: 'unsupported', reason: 'JAMENDO_NOT_CONFIGURED',
    });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('allows a track with a Creative Commons Attribution license', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ headers: { status: 'success', code: 0 }, results: [{
        id: '12345', name: 'Open Road', artist_name: 'Test Artist',
        license_ccurl: 'https://creativecommons.org/licenses/by/4.0/',
      }] }),
    }) as unknown as typeof fetch;
    await expect(adapter.getAvailability('12345')).resolves.toMatchObject({
      kind: 'ok', value: { available: true },
    });
  });

  it('blocks non-commercial tracks unless Breezze is explicitly configured as non-commercial', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ headers: { status: 'success', code: 0 }, results: [{
        id: '12345', name: 'Open Road', artist_name: 'Test Artist',
        license_ccurl: 'https://creativecommons.org/licenses/by-nc-sa/4.0/',
      }] }),
    }) as unknown as typeof fetch;
    await expect(adapter.getAvailability('12345')).resolves.toMatchObject({
      kind: 'ok', value: { available: false },
    });
    process.env.BREEZZE_NONCOMMERCIAL = 'true';
    await expect(adapter.getAvailability('12345')).resolves.toMatchObject({
      kind: 'ok', value: { available: true },
    });
  });

  it('resolves only Jamendo-controlled HTTPS stream redirects', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false, status: 302,
      headers: { get: (name: string) => name === 'location'
        ? 'https://prod-1.storage.jamendo.com/track.mp3' : null },
    }) as unknown as typeof fetch;
    const result = await adapter.resolvePlayback({
      providerTrackId: '12345', territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: 'Jamendo CC BY' },
    });
    expect(result).toMatchObject({ kind: 'ok', value: { codec: 'mp3', mimeType: 'audio/mpeg' } });
  });

  it('rejects stream redirects to untrusted hosts', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false, status: 302,
      headers: { get: (name: string) => name === 'location'
        ? 'https://attacker.example/audio.mp3' : null },
    }) as unknown as typeof fetch;
    await expect(adapter.resolvePlayback({
      providerTrackId: '12345', territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    })).resolves.toMatchObject({
      kind: 'error', code: 'JAMENDO_STREAM_HOST_REJECTED',
    });
  });
});
